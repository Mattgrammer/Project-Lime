import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hexcolor/hexcolor.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Import the separate page files
import 'teacher_home_page.dart';
import 'teacher_inbox_page.dart';
import 'teacher_about_page.dart';
import 'my_classes_page.dart';
import 'teacher_schedule_page.dart';
import 'unassigned_students_page.dart';
import '../../widgets/delete_account_dialog.dart';
import '../../widgets/lime_dropdown.dart';
import '../common/processing_deletion_page.dart';

class ProfileTeacherPage extends StatefulWidget {
  const ProfileTeacherPage({super.key});

  @override
  State<ProfileTeacherPage> createState() => _ProfileTeacherPageState();
}

class _ProfileTeacherPageState extends State<ProfileTeacherPage> {
  int _selectedIndex = 0;
  bool _detailsSubmitted = false;
  bool _isLoading = true;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _accessCodeController = TextEditingController();
  String? _selectedUserType;
  String? _selectedTeacherType;
  File? _profileImage;

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

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _accessCodeController.dispose();
    super.dispose();
  }

  Future<void> _loadProfileData() async {
    final user = _auth.currentUser;

    if (user != null) {
      try {
        var doc = await _firestore.collection('teachers').doc(user.uid).get();
        var fromTeachers = false;
        if (!doc.exists) {
          doc = await _firestore.collection('students').doc(user.uid).get();
        } else {
          fromTeachers = true;
        }

        if (doc.exists) {
          final data = doc.data()!;

          final name = data['name'] as String? ?? '';
          final userType = fromTeachers ? 'Teacher' : data['userType'] as String?;
          final teacherType = data['teacherType'] as String?;
          final detailsSubmitted = data['detailsSubmitted'] as bool? ?? false;
          final imgPath = data['profileImagePath'] as String?;

          setState(() {
            _nameController.text = name;
            _selectedUserType = userType;
            _selectedTeacherType = teacherType;
            _detailsSubmitted = detailsSubmitted;

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

  Future<void> _saveProfileData() async {
    final user = _auth.currentUser;

    if (user != null) {
      try {
        final collection = (_selectedUserType == 'Teacher') ? 'teachers' : 'students';
        final docRef = _firestore.collection(collection).doc(user.uid);

        final snap = await docRef.get();
        final dataToSave = {
          'uid': user.uid,
          'name': _nameController.text,
          'email': user.email ?? '',
          'userType': _selectedUserType,
          'detailsSubmitted': true,
        };
        if (_selectedTeacherType != null) {
          dataToSave['teacherType'] = _selectedTeacherType;
        }
        if (_profileImage != null) {
          dataToSave['profileImagePath'] = _profileImage!.path;
        }

        if (!snap.exists || (snap.data()?['createdAt'] == null)) {
          dataToSave['createdAt'] = FieldValue.serverTimestamp();
        }

        await docRef.set(dataToSave, SetOptions(merge: true));

        // If saving as Teacher, delete the student document if it exists
        if (_selectedUserType == 'Teacher') {
          try {
            final studentDocRef = _firestore.collection('students').doc(user.uid);
            final studentSnap = await studentDocRef.get();
            if (studentSnap.exists) {
              final studentData = studentSnap.data();
              if (studentData != null && (user.email == null || user.email!.isEmpty)) {
                final studentEmail = studentData['email'] as String?;
                if (studentEmail != null && studentEmail.isNotEmpty) {
                  await docRef.set({'email': studentEmail}, SetOptions(merge: true));
                }
              }
              await studentDocRef.delete();
              debugPrint('Deleted student document for teacher: ${user.uid}');
            }
          } catch (e) {
            debugPrint('Error deleting student document: $e');
          }
        }
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
    }

    // If user chooses Teacher, validate access code before saving
    if (_selectedUserType == 'Teacher') {
      final code = _accessCodeController.text.trim();
        if (code.length != 12 ||
            !RegExp(r'[A-Z]').hasMatch(code) ||
            !RegExp(r'[a-z]').hasMatch(code) ||
            !RegExp(r'\d').hasMatch(code) ||
            !RegExp(r'[^A-Za-z0-9]').hasMatch(code)) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Access code must be 12 characters and include upper, lower, number and a special character')));
          return;
        }

      // Verify code against server-stored codes (Firestore: collection 'config', doc 'registration', field 'teacher_codes')
      try {
        final firestore = _firestore;
        List<String> codes = [];

        final regDoc = await firestore.collection('config').doc('registration').get();
        var raw = regDoc.data()?['teacher_codes'];
        if (raw is List) {
          codes = raw.map((e) => e?.toString().trim() ?? '').where((s) => s.isNotEmpty).toList();
        }

        // Fallback: search all docs under 'config' for teacher_codes
        if (codes.isEmpty) {
          final all = await firestore.collection('config').get();
          for (var d in all.docs) {
            final r = d.data()['teacher_codes'];
            if (r is List) {
              codes = r.map((e) => e?.toString().trim() ?? '').where((s) => s.isNotEmpty).toList();
              if (codes.isNotEmpty) break;
            }
          }
        }

        if (!codes.contains(code)) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid access code')));
          return;
        }
      } catch (e) {
        debugPrint('Error verifying access code: $e');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unable to verify access code')));
        return;
      }
    }

    await _saveProfileData();
    if (!mounted) return;
    
    // If student, navigate to home to trigger router redirection
    if (_selectedUserType == 'Student') {
       Navigator.pushReplacementNamed(context, '/home');
    } else {
       // If teacher, just update local state to show dashboard
       setState(() => _detailsSubmitted = true);
    }
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

  Widget _buildDropdown<T>({
    required String label,
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required Function(T?) onChanged,
  }) {
    return LIMEDropdown<T>(
      label: label,
      value: value,
      items: items,
      onChanged: onChanged,
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
                _selectedTeacherType ?? '',
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
              _menuItem(Icons.schedule, 'Schedule', 1),
              _menuItem(Icons.class_, 'My Classes', 2),
              if (_selectedTeacherType == 'Adviser') _menuItem(Icons.person_add, 'Unassigned Students', 5),
              
              // Inbox with Stream for real-time badge
              StreamBuilder<QuerySnapshot>(
                stream: _auth.currentUser != null 
                    ? _firestore.collection('teachers').doc(_auth.currentUser!.uid).collection('inbox').where('read', isEqualTo: false).snapshots()
                    : null,
                builder: (context, snapshot) {
                  int unreadCount = 0;
                  if (snapshot.hasData) {
                    unreadCount = snapshot.data!.docs.length;
                  }
                  
                  return _menuItem(
                    Icons.inbox, 
                    'Inbox', 
                    3,
                    trailing: unreadCount > 0 
                        ? Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              unreadCount > 99 ? '99+' : unreadCount.toString(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                ),
                              ),
                            )
                        : null,
                    );
                }
              ),
              
              _menuItem(Icons.info, 'About', 4),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
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
                            _buildDropdown<String>(
                              label: 'User Type',
                              value: _selectedUserType,
                              items: userTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                              onChanged: (v) => setState(() {
                                _selectedUserType = v;
                                // Reset teacher type when user type changes
                                if (v != 'Teacher') {
                                  _selectedTeacherType = null;
                                }
                              }),
                            ),
                            const SizedBox(height: 16),
                            // Show teacher type dropdown only if teacher is selected
                            if (_selectedUserType == 'Teacher') ...[
                              _buildDropdown<String>(
                                label: 'Teacher Type',
                                value: _selectedTeacherType,
                                items: teacherTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                                onChanged: (v) =>
                                    setState(() => _selectedTeacherType = v),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                key: const ValueKey('access_code_field'),
                                controller: _accessCodeController,
                                decoration: const InputDecoration(
                                  labelText: 'Teacher Access Code',
                                  hintText: 'Enter 12-character access code',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ],
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
      {VoidCallback? onTap, Widget? trailing}) {
    return ListTile(
      leading: Icon(icon, color: Colors.white),
      title: Text(label, style: const TextStyle(color: Colors.white)),
      trailing: trailing,
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
        return TeacherHomePage(
          onNavigate: (index) => setState(() => _selectedIndex = index),
        );
      case 1:
        return const TeacherSchedulePage();
      case 2:
        return const MyClassesPage();
      case 3:
        return const TeacherInboxPage();
      case 4:
        return const TeacherAboutPage();
      case 5:
        return const UnassignedStudentsPage();
      default:
        return const TeacherHomePage();
    }
  }
}
