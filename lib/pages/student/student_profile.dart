import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hexcolor/hexcolor.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Import the separate page files
import 'home_page.dart';
import 'enrollment_page.dart';
import 'schedule_page.dart';
import 'grades_page.dart';
import 'inbox_page.dart';
import 'about_page.dart';

class ProfileStudentPage extends StatefulWidget {
  const ProfileStudentPage({super.key});

  @override
  State<ProfileStudentPage> createState() => _ProfileStudentPageState();
}

class _ProfileStudentPageState extends State<ProfileStudentPage> {
  int _selectedIndex = 0;
  bool _detailsSubmitted = false;
  bool _isLoading = true;

  final TextEditingController _nameController = TextEditingController();
  String? _selectedGradeLevel;
  String? _selectedTrackStrand;
  File? _profileImage;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final List<String> gradeLevels = [
    'Grade 11',
    'Grade 12',
  ];

  final List<String> trackStrands = [
    'STEM',
    'ABM',
    'HUMSS',
    'GAS',
    'TVL',
  ];

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  // ================= LOAD PROFILE =================
  Future<void> _loadProfileData() async {
    final prefs = await SharedPreferences.getInstance();
    final user = _auth.currentUser;

    // First, try to load from Firestore if user is authenticated
    if (user != null) {
      try {
        final doc = await _firestore.collection('students').doc(user.uid).get();
        if (doc.exists) {
          final data = doc.data()!;
          
          // Load from Firestore and sync to SharedPreferences
          final name = data['name'] as String? ?? '';
          final grade = data['gradeLevel'] as String?;
          final track = data['trackStrand'] as String?;
          final detailsSubmitted = data['detailsSubmitted'] as bool? ?? false;

          // Update SharedPreferences with Firestore data
          await prefs.setString('student_name', name);
          if (grade != null) {
            await prefs.setString('student_grade', grade);
          }
          if (track != null) {
            await prefs.setString('student_track', track);
          }
          await prefs.setBool('details_submitted', detailsSubmitted);

          // Update UI state
          setState(() {
            _nameController.text = name;
            _selectedGradeLevel = grade;
            _selectedTrackStrand = track;
            _detailsSubmitted = detailsSubmitted;

            final imgPath = prefs.getString('student_image');
            if (imgPath != null && File(imgPath).existsSync()) {
              _profileImage = File(imgPath);
            }

            _isLoading = false;
          });
          return;
        }
      } catch (e) {
        debugPrint('Error loading from Firestore: $e');
        // Fall through to load from SharedPreferences
      }
    }

    // Fallback: Load from SharedPreferences
    setState(() {
      _nameController.text = prefs.getString('student_name') ?? '';
      _selectedGradeLevel = prefs.getString('student_grade');
      _selectedTrackStrand = prefs.getString('student_track');

      // Primary check: use the explicit flag
      _detailsSubmitted = prefs.getBool('details_submitted') ?? false;

      final imgPath = prefs.getString('student_image');
      if (imgPath != null && File(imgPath).existsSync()) {
        _profileImage = File(imgPath);
      }

      // Secondary check: if all required data exists, mark as submitted
      if (!_detailsSubmitted &&
          _nameController.text.isNotEmpty &&
          _selectedGradeLevel != null &&
          _selectedGradeLevel!.isNotEmpty &&
          _selectedTrackStrand != null &&
          _selectedTrackStrand!.isNotEmpty) {
        _detailsSubmitted = true;
      }

      _isLoading = false;
    });
  }

  // ================= SAVE PROFILE =================
  Future<void> _saveProfileData() async {
    final prefs = await SharedPreferences.getInstance();
    final user = _auth.currentUser;

    // Save to SharedPreferences
    await prefs.setString('student_name', _nameController.text);
    await prefs.setString('student_grade', _selectedGradeLevel!);
    await prefs.setString('student_track', _selectedTrackStrand!);
    await prefs.setBool('details_submitted', true);
    if (_profileImage != null) {
      await prefs.setString('student_image', _profileImage!.path);
    }

    // Save to Firestore if user is authenticated
    if (user != null) {
      try {
        await _firestore.collection('students').doc(user.uid).set({
          'name': _nameController.text,
          'gradeLevel': _selectedGradeLevel,
          'trackStrand': _selectedTrackStrand,
          'detailsSubmitted': true,
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('Error saving to Firestore: $e');
        // Continue even if Firestore save fails
      }
    }
  }

  // ================= IMAGE PICKER (DESKTOP + MOBILE) =================
  Future<void> _pickImage() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final result = await FilePicker.platform.pickFiles(type: FileType.image);
      if (result != null && result.files.single.path != null) {
        setState(() {
          _profileImage = File(result.files.single.path!);
        });
      }
    } else {
      final picker = ImagePicker();
      final image = await picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        setState(() => _profileImage = File(image.path));
      }
    }
  }

  // ================= SUBMIT PROFILE =================
  void _submitDetails() async {
    if (_nameController.text.isEmpty ||
        _selectedGradeLevel == null ||
        _selectedTrackStrand == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields')),
      );
      return;
    }

    await _saveProfileData();
    if (!mounted) return;
    setState(() => _detailsSubmitted = true);
  }

  // ================= LOGOUT (CLEAR DATA) =================
  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('student_name');
    await prefs.remove('student_grade');
    await prefs.remove('student_track');
    await prefs.remove('student_image');
    await prefs.remove('details_submitted');

    // Sign out from Firebase
    await _auth.signOut();

    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/signin', (_) => false);
  }

  // ================= BUILD SIDEBAR CONTENT =================
  Widget _buildDropdown({
    required String label,
    required String? value,
    required List<String> items,
    required Function(String?) onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey),
        borderRadius: BorderRadius.circular(4),
      ),
      child: PopupMenuButton<String>(
        onSelected: (val) => onChanged(val),
        itemBuilder: (BuildContext context) => items
            .map((item) => PopupMenuItem<String>(
          value: item,
          child: Text(item),
        ))
            .toList(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                value ?? label,
                style: TextStyle(
                  color: value == null ? Colors.grey[600] : Colors.black,
                  fontSize: 16,
                ),
              ),
              Icon(Icons.arrow_drop_down, color: HexColor("#0F4C7F")),
            ],
          ),
        ),
      ),
    );
  }

  // ================= BUILD SIDEBAR CONTENT =================
  Widget _buildSidebarContent() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
          child: Column(
            children: [
              CircleAvatar(
                radius: 38,
                backgroundColor: Colors.white,
                backgroundImage: _profileImage != null
                    ? FileImage(_profileImage!)
                    : null,
                child: _profileImage == null
                    ? Icon(Icons.person,
                    size: 40, color: HexColor("#0F4C7F"))
                    : null,
              ),
              const SizedBox(height: 14),
              Text(
                _nameController.text,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                _selectedTrackStrand ?? '',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
              ),
              Text(
                _selectedGradeLevel ?? '',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
              ),
            ],
          ),
        ),
        const Divider(color: Colors.white24),
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              _menuItem(Icons.home, 'Home', 0),
              _menuItem(Icons.assignment, 'Enrollment', 1),
              _menuItem(Icons.schedule, 'Schedule', 2),
              _menuItem(Icons.grade, 'Grades', 3),
              _menuItem(Icons.inbox, 'Inbox', 4),
              _menuItem(Icons.info, 'About', 5),
              const Divider(color: Colors.white24),
              _menuItem(Icons.logout, 'Logout', -1, onTap: _logout),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width <= 600;
    final isDesktop = width > 900;

    // Show loading screen while data is being loaded
    if (_isLoading) {
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(HexColor("#0F4C7F")),
          ),
        ),
      );
    }

    // ================= PROFILE FORM =================
    if (!_detailsSubmitted) {
      return Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 520),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 30,
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: HexColor("#0F4C7F"),
                      borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(24)),
                    ),
                    child: const Text(
                      'Complete Your Profile',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        GestureDetector(
                          onTap: _pickImage,
                          child: CircleAvatar(
                            radius: 48,
                            backgroundColor: Colors.grey[200],
                            backgroundImage: _profileImage != null
                                ? FileImage(_profileImage!)
                                : null,
                            child: _profileImage == null
                                ? Icon(Icons.camera_alt,
                                size: 30, color: HexColor("#0F4C7F"))
                                : null,
                          ),
                        ),
                        const SizedBox(height: 24),
                        TextField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            labelText: 'Full Name',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildDropdown(
                          label: 'Grade Level',
                          value: _selectedGradeLevel,
                          items: gradeLevels,
                          onChanged: (v) =>
                              setState(() => _selectedGradeLevel = v),
                        ),
                        const SizedBox(height: 16),
                        _buildDropdown(
                          label: 'Track / Strand',
                          value: _selectedTrackStrand,
                          items: trackStrands,
                          onChanged: (v) =>
                              setState(() => _selectedTrackStrand = v),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _submitDetails,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: HexColor("#0F4C7F"),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                            ),
                            child: const Text(
                              'Continue',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // ================= DASHBOARD =================
    return Scaffold(
      appBar: isMobile
          ? AppBar(
        title: Text(_nameController.text),
        backgroundColor: HexColor("#0F4C7F"),
        iconTheme: const IconThemeData(color: Colors.white),
      )
          : null,
      drawer: isMobile
          ? Drawer(
        child: Container(
          color: HexColor("#0F4C7F"),
          child: _buildSidebarContent(),
        ),
      )
          : null,
      body: Row(
        children: [
          if (!isMobile)
            Container(
              width: isDesktop ? 280 : 240,
              color: HexColor("#0F4C7F"),
              child: _buildSidebarContent(),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _buildContent(_selectedIndex),
            ),
          ),
        ],
      ),
    );
  }

  Widget _menuItem(IconData icon, String label, int index,
      {VoidCallback? onTap}) {
    return ListTile(
      leading: Icon(icon, color: Colors.white),
      title: Text(label, style: const TextStyle(color: Colors.white)),
      selected: _selectedIndex == index,
      selectedTileColor: Colors.white.withValues(alpha: 0.2),
      onTap: () {
        // Close drawer first if it's open (mobile only)
        final scaffoldState = Scaffold.maybeOf(context);
        if (scaffoldState != null && scaffoldState.isDrawerOpen) {
          Navigator.pop(context);
        }

        // Then execute the action
        if (onTap != null) {
          onTap();
        } else {
          setState(() => _selectedIndex = index);
        }
      },
    );
  }

  Widget _buildContent(int index) {
    switch (index) {
      case 0:
        return const HomePage();
      case 1:
        return const EnrollmentPage();
      case 2:
        return const SchedulePage();
      case 3:
        return const GradesPage();
      case 4:
        return const InboxPage();
      case 5:
        return const AboutPage();
      default:
        return const HomePage();
    }
  }
}