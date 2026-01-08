import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hexcolor/hexcolor.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Import the separate page files
import 'home_page.dart';
import 'subjects_page.dart';
import 'schedule_page.dart';
import 'grades_page.dart';
import 'inbox_page.dart';
import 'about_page.dart';
import 'request_section_page.dart';

import '../../widgets/delete_account_dialog.dart';
import '../common/processing_deletion_page.dart';

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
  String? _selectedUserType;
  String? _selectedTeacherType;
  String? _selectedGradeLevel;
  String? _selectedTrackStrand;
  File? _profileImage;
  List<String> _assignedSections = [];

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final List<String> userTypes = [
    'Student',
    'Teacher',
  ];

  final List<String> teacherTypes = [
    'Subject Teacher',
    'Adviser',
  ];

  final List<String> gradeLevels = [
    'Grade 11',
    'Grade 12',
  ];

  final List<String> trackStrands = [
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
    final user = _auth.currentUser;

    if (user != null) {
      try {
        final doc = await _firestore.collection('students').doc(user.uid).get();
        if (doc.exists) {
          final data = doc.data()!;
          
          final name = data['name'] as String? ?? '';
          final userType = data['userType'] as String?;
          final teacherType = data['teacherType'] as String?;
          final grade = data['gradeLevel'] as String?;
          final track = data['trackStrand'] as String?;
          final detailsSubmitted = data['detailsSubmitted'] as bool? ?? false;
          final sections = data['sections'] as List<dynamic>?;
          final sectionsList = sections != null ? sections.map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).toList() : <String>[];
          final imgPath = data['profileImagePath'] as String?;

          setState(() {
            _nameController.text = name;
            _selectedUserType = userType;
            _selectedTeacherType = teacherType;
            _selectedGradeLevel = grade;
            _selectedTrackStrand = track;
            _detailsSubmitted = detailsSubmitted;
            _assignedSections = sectionsList;

            if (imgPath != null && File(imgPath).existsSync()) {
              _profileImage = File(imgPath);
            }

            _isLoading = false;
          });
          return;
        }
      } catch (e) {
        debugPrint('Error loading from Firestore: $e');
      }
    }

    setState(() {
      _isLoading = false;
    });
  }

  // ================= SAVE PROFILE =================
  Future<void> _saveProfileData() async {
    final user = _auth.currentUser;

    if (user != null) {
      try {
        final dataToSave = {
          'name': _nameController.text,
          'userType': _selectedUserType,
          'detailsSubmitted': true,
        };
        
        if (_selectedTeacherType != null) {
          dataToSave['teacherType'] = _selectedTeacherType;
        }
        if (_selectedGradeLevel != null) {
          dataToSave['gradeLevel'] = _selectedGradeLevel;
        }
        if (_selectedTrackStrand != null) {
          dataToSave['trackStrand'] = _selectedTrackStrand;
        }
        if (_profileImage != null) {
          dataToSave['profileImagePath'] = _profileImage!.path;
        }
        
        await _firestore.collection('students').doc(user.uid).set(
          dataToSave,
          SetOptions(merge: true),
        );
      } catch (e) {
        debugPrint('Error saving to Firestore: $e');
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
    if (_nameController.text.isEmpty || _selectedUserType == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all required fields')),
      );
      return;
    }

    // Validate based on user type
    if (_selectedUserType == 'Teacher') {
      if (_selectedTeacherType == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select teacher type')),
        );
        return;
      }
    } else if (_selectedUserType == 'Student') {
      if (_selectedGradeLevel == null || _selectedTrackStrand == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please fill in all student fields')),
        );
        return;
      }
    }

    await _saveProfileData();
    if (!mounted) return;
    setState(() => _detailsSubmitted = true);
  }

  // ================= DELETE ACCOUNT =================
  Future<void> _deleteAccount() async {
    // Show warning dialog with countdown and password field
    final password = await showDeleteAccountDialog(context);
    
    if (password == null || password.isEmpty) return;
    if (!mounted) return;

    // Navigate to isolated processing page to kill all dashboard streams
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => ProcessingDeletionPage(password: password),
      ),
      (_) => false, // Remove all previous routes
    );
  }

  // ================= LOGOUT (CLEAR DATA) =================
  Future<void> _logout() async {
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
    return _DownwardDropdownField(
      label: label,
      value: value,
      items: items,
      onChanged: (v) => onChanged(v),
      arrowColor: HexColor("#0F4C7F"),
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
              if ((_assignedSections.isNotEmpty))
                Text(
                  _assignedSections.join(', '),
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontWeight: FontWeight.bold),
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
              _menuItem(Icons.assignment, 'Subjects', 1),
              _menuItem(Icons.schedule, 'Schedule', 2),
              _menuItem(Icons.grade, 'Grades', 3),
              _menuItem(Icons.inbox, 'Inbox', 4),
              _menuItem(Icons.person_add, 'Request Section', 6),
              _menuItem(Icons.info, 'About', 5),
              const Divider(color: Colors.white24),
              _menuItem(Icons.delete_forever, 'Delete Account', -2, onTap: _deleteAccount),
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
                    color: Colors.black.withValues(alpha: 0.08),
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
                          label: 'User Type',
                          value: _selectedUserType,
                          items: userTypes,
                          onChanged: (v) => setState(() {
                            _selectedUserType = v;
                            // Reset teacher type and student fields when user type changes
                            if (v != 'Teacher') {
                              _selectedTeacherType = null;
                            }
                            if (v != 'Student') {
                              _selectedGradeLevel = null;
                              _selectedTrackStrand = null;
                            }
                          }),
                        ),
                        const SizedBox(height: 16),
                        // Show teacher type dropdown only if teacher is selected
                        if (_selectedUserType == 'Teacher')
                          _buildDropdown(
                            label: 'Teacher Type',
                            value: _selectedTeacherType,
                            items: teacherTypes,
                            onChanged: (v) =>
                                setState(() => _selectedTeacherType = v),
                          ),
                        if (_selectedUserType == 'Teacher')
                          const SizedBox(height: 16),
                        // Show student fields only if student is selected
                        if (_selectedUserType == 'Student')
                          _buildDropdown(
                            label: 'Grade Level',
                            value: _selectedGradeLevel,
                            items: gradeLevels,
                            onChanged: (v) =>
                                setState(() => _selectedGradeLevel = v),
                          ),
                        if (_selectedUserType == 'Student')
                          const SizedBox(height: 16),
                        if (_selectedUserType == 'Student')
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isMobile = width <= 600;
        final isDesktop = width > 900;

        return Scaffold(
          appBar: isMobile
              ? AppBar(
            title: Text(_nameController.text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            backgroundColor: HexColor("#0F4C7F"),
            iconTheme: const IconThemeData(color: Colors.white),
            leading: Builder(
              builder: (context) => IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
            ),
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
      },
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
        return const SubjectsPage();
      case 2:
        return const SchedulePage();
      case 3:
        return const GradesPage();
      case 4:
        return const InboxPage();
      case 5:
        return const AboutPage();
      case 6:
        return const RequestSectionPage();
      default:
        return const HomePage();
    }
  }
}

class _DownwardDropdownField extends StatefulWidget {
  const _DownwardDropdownField({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    required this.arrowColor,
  });

  final String label;
  final String? value;
  final List<String> items;
  final ValueChanged<String?> onChanged;
  final Color arrowColor;

  @override
  State<_DownwardDropdownField> createState() => _DownwardDropdownFieldState();
}

class _DownwardDropdownFieldState extends State<_DownwardDropdownField> {
  final LayerLink _link = LayerLink();
  final GlobalKey _targetKey = GlobalKey();
  OverlayEntry? _entry;

  @override
  void dispose() {
    _removeEntry();
    super.dispose();
  }

  void _removeEntry() {
    _entry?.remove();
    _entry = null;
  }

  void _toggle() {
    if (_entry != null) {
      _removeEntry();
      return;
    }

    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;

    final renderBox = _targetKey.currentContext?.findRenderObject() as RenderBox?;
    final offset = renderBox?.localToGlobal(Offset.zero);
    final size = renderBox?.size;
    if (offset == null || size == null) return;

    final screenHeight = MediaQuery.of(context).size.height;
    final availableHeight = (screenHeight - (offset.dy + size.height) - 8).clamp(120.0, 320.0);

    _entry = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _removeEntry,
              ),
            ),
            CompositedTransformFollower(
              link: _link,
              showWhenUnlinked: false,
              offset: Offset(0, size.height + 4),
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(8),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: size.width,
                    maxWidth: size.width,
                    maxHeight: availableHeight,
                  ),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: widget.items.length,
                    itemBuilder: (context, index) {
                      final item = widget.items[index];
                      final selected = item == widget.value;
                      return ListTile(
                        dense: true,
                        title: Text(item),
                        trailing: selected ? const Icon(Icons.check) : null,
                        onTap: () {
                          widget.onChanged(item);
                          _removeEntry();
                        },
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    overlay.insert(_entry!);
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: InkWell(
        key: _targetKey,
        borderRadius: BorderRadius.circular(4),
        onTap: _toggle,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: widget.label,
            border: const OutlineInputBorder(),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  widget.value ?? '',
                  style: TextStyle(
                    color: widget.value == null ? Colors.grey[600] : Colors.black,
                    fontSize: 16,
                  ),
                ),
              ),
              Icon(Icons.arrow_drop_down, color: widget.arrowColor),
            ],
          ),
        ),
      ),
    );
  }
}