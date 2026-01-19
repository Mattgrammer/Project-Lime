import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hexcolor/hexcolor.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// Firebase Storage removed - requires paid plan
import 'package:google_fonts/google_fonts.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'dart:convert'; // Needed for base64Decode

// Import the separate page files
import 'home_page.dart';
import 'subjects_page.dart';
import 'grades_page.dart';
import 'inbox_page.dart';
import 'about_page.dart';
import 'request_section_page.dart';

import '../../widgets/delete_account_dialog.dart';
import '../common/processing_deletion_page.dart';
import '../../widgets/connectivity_indicator.dart';
import '../common/help_page.dart';

class ProfileStudentPage extends StatefulWidget {
  const ProfileStudentPage({super.key});

  @override
  State<ProfileStudentPage> createState() => _ProfileStudentPageState();
}

class _ProfileStudentPageState extends State<ProfileStudentPage> {
  int _selectedIndex = 2; // Default to Home
  bool _startTour = false;
  bool _detailsSubmitted = false;
  bool _isLoading = true;
  bool _isLoadingProfile = false;
  StreamSubscription? _profileSubscription;
  
  // SHARED DATA LAYER
  Stream<QuerySnapshot>? _sectionsStream;
  final List<Widget?> _pages = List.filled(6, null); // Lazy-loaded pages

  final TextEditingController _nameController = TextEditingController();
  String? _selectedUserType;
  String? _selectedTeacherType;
  String? _selectedGradeLevel;
  File? _profileImage;
  String? _profileImageUrl;
  String? _profileImageThumbnail;
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

  // Navigation Keys
  final GlobalKey _navScheduleKey = GlobalKey();
  final GlobalKey _navClassesKey = GlobalKey();
  final GlobalKey _navGradesKey = GlobalKey();
  final GlobalKey _navInboxKey = GlobalKey();
  final GlobalKey _navProfileKey = GlobalKey();
  final GlobalKey _navHelpKey = GlobalKey();
  final GlobalKey _navHomeKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadProfileData();
    _initSectionsStream();
  }

  void _initSectionsStream() {
    final user = _auth.currentUser;
    if (user != null) {
      _sectionsStream = _firestore
          .collection('sections')
          .where('studentUids', arrayContains: user.uid)
          .snapshots();
    }
  }

  Widget _getPage(int index) {
    if (_pages[index] != null) return _pages[index]!;

    switch (index) {
      case 0:
        _pages[index] = SubjectsPage(sectionsStream: _sectionsStream);
        break;
      case 1:
        _pages[index] = GradesPage(sectionsStream: _sectionsStream);
        break;
      case 2:
        _pages[index] = HomePage(
          onNavigate: (i) => setState(() => _selectedIndex = i),
          startTour: _startTour,
          scheduleKey: _navScheduleKey,
          classesKey: _navClassesKey,
          gradesKey: _navGradesKey,
          inboxKey: _navInboxKey,
          profileKey: _navProfileKey,
          helpKey: _navHelpKey,
          profileImagePath: _profileImage?.path,
          profileImageThumbnail: _profileImageThumbnail,
          profileImageUrl: _profileImageUrl,
        );
        break;
      case 3:
        _pages[index] = HelpPage(
          onStartTour: () {
            setState(() {
              _selectedIndex = 2;
              _startTour = true;
              _pages[2] = null; // Force rebuild with tour
            });
            Future.delayed(const Duration(milliseconds: 100), () {
              if (mounted) {
                setState(() {
                  _startTour = false;
                });
              }
            });
          },
          userType: 'Student',
        );
        break;
      case 4:
        _pages[index] = const InboxPage();
        break;
      case 5:
        _pages[index] = _buildProfileTab();
        break;
    }
    return _pages[index]!;
  }

  @override
  void dispose() {
    _profileSubscription?.cancel();
    _nameController.dispose();
    super.dispose();
  }

  // ================= LOAD PROFILE =================
  void _loadProfileData() {
    final user = _auth.currentUser;

    if (user == null || _isLoadingProfile) {
      if (mounted && user == null) setState(() => _isLoading = false);
      return;
    }

    _isLoadingProfile = true;
    _profileSubscription?.cancel();
    
    _profileSubscription = _firestore.collection('students').doc(user.uid).snapshots().listen((doc) {
      _isLoadingProfile = false;
      if (!mounted) return;
      
      try {
        if (doc.exists) {
          final data = doc.data()!;
          
          final name = data['name'] as String? ?? '';
          final userType = data['userType'] as String?;
          final teacherType = data['teacherType'] as String?;
          final grade = data['gradeLevel'] as String?;
          final detailsSubmitted = data['detailsSubmitted'] as bool? ?? false;
          final sections = data['sections'] as List<dynamic>?;
          final sectionsList = sections != null ? sections.map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).toList() : <String>[];
          final imgPath = data['profileImagePath'] as String?;
          final imgUrl = data['profileImageUrl'] as String?;

          setState(() {
            _nameController.text = name;
            _selectedUserType = userType;
            _selectedTeacherType = teacherType;
            _selectedGradeLevel = grade;
            _detailsSubmitted = detailsSubmitted;
            _assignedSections = sectionsList;
            _profileImageUrl = imgUrl;
            _profileImageThumbnail = data['profileImageThumbnail'] as String?;

            if (imgPath != null && File(imgPath).existsSync()) {
              _profileImage = File(imgPath);
            } else {
              _profileImage = null; 
            }
          });
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }, onError: (e) {
      _isLoadingProfile = false;
      debugPrint('Error listening to profile: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    });
  }

  // ================= SAVE PROFILE =================
  Future<String?> _generateThumbnail(File file) async {
    try {
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        return null; 
      }
      
      final result = await FlutterImageCompress.compressWithFile(
        file.absolute.path,
        minWidth: 200,
        minHeight: 200,
        quality: 50,
      );
      if (result != null) {
        return base64Encode(result);
      }
    } catch (e) {
      debugPrint("Error generating thumbnail: $e");
    }
    return null;
  }

  Future<void> _saveProfileData() async {
    final user = _auth.currentUser;

    if (user != null) {
      try {
        final dataToSave = {
          'name': _nameController.text,
          'userType': _selectedUserType,
          'detailsSubmitted': true,
          'hasSeenWelcome': true,
        };
        
        if (_selectedTeacherType != null) {
          dataToSave['teacherType'] = _selectedTeacherType;
        }
        if (_selectedGradeLevel != null) {
          dataToSave['gradeLevel'] = _selectedGradeLevel;
        }
      
        if (_profileImage != null) {
          dataToSave['profileImagePath'] = _profileImage!.path;
          
          final thumbnail = await _generateThumbnail(_profileImage!);
          if (thumbnail != null) {
            dataToSave['profileImageThumbnail'] = thumbnail;
          }
        }

        await _firestore.collection('students').doc(user.uid).set(
          dataToSave,
          SetOptions(merge: true),
        );
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Profile updated successfully!')),
          );
        }

        // Update Firebase Auth display name
        await user.updateDisplayName(_nameController.text);
        await user.reload();
      } catch (e) {
        debugPrint('Error saving to Firestore: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error saving profile: $e')),
          );
        }
        rethrow;
      }
    }
  }

  // ================= IMAGE PICKER (DESKTOP + MOBILE) =================
  Future<File?> _pickImage() async {
    File? selectedFile;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final result = await FilePicker.platform.pickFiles(type: FileType.image);
      if (result != null && result.files.single.path != null) {
        selectedFile = File(result.files.single.path!);
      }
    } else {
      final picker = ImagePicker();
      final image = await picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        selectedFile = File(image.path);
      }
    }

    if (selectedFile != null) {
      if (!mounted) return null; // Check mounted before using context
      // Only crop on non-desktop platforms as image_cropper handles them better
      if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
        final croppedFile = await ImageCropper().cropImage(
          sourcePath: selectedFile.path,
          aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
          uiSettings: [
            AndroidUiSettings(
              toolbarTitle: 'Crop Profile Photo',
              toolbarColor: HexColor("#116754"),
              toolbarWidgetColor: Colors.white,
              initAspectRatio: CropAspectRatioPreset.square,
              lockAspectRatio: true,
              hideBottomControls: true,
            ),
            IOSUiSettings(
              title: 'Crop Profile Photo',
            ),
            WebUiSettings(
              context: context,
              // Removed problematic size and presentStyle for now to fix build
            ),
          ],
        );
        if (croppedFile != null) {
          return File(croppedFile.path);
        }
      } else {
        return selectedFile;
      }
    }
    return null;
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
      if (_selectedGradeLevel == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select grade level')),
        );
        return;
      }
    }

    try {
    await _saveProfileData();
  } catch (e) {
    // Error SnackBar already shown in _saveProfileData
    return;
  }
  
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

  void _showEditProfileSheet() {
    final TextEditingController nameEditController = TextEditingController(text: _nameController.text);
    String? tempGrade = _selectedGradeLevel;
    File? tempProfileImage = _profileImage; // Temporary holding for image

    showDialog(
      context: context,
      builder: (context) => Center( // Wrap with Center for perfect middle alignment
        child: Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          backgroundColor: Colors.white,
          child: ConstrainedBox( // Use ConstrainedBox for better control
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: SingleChildScrollView(
                child: StatefulBuilder(builder: (context, setSheetState) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Edit Profile',
                        style: GoogleFonts.merriweather(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: HexColor("#116754"),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Stack(
                        children: [
                          CircleAvatar(
                            radius: 50,
                            backgroundColor: HexColor("#116754").withValues(alpha: 0.1),
                            backgroundImage: tempProfileImage != null
                                ? FileImage(tempProfileImage!)
                                : (_profileImageUrl != null ? NetworkImage(_profileImageUrl!) : null) as ImageProvider?,
                            child: (tempProfileImage == null && _profileImageUrl == null)
                                ? Icon(Icons.person, size: 50, color: HexColor("#116754"))
                                : null,
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: GestureDetector(
                              onTap: () async {
                                final picked = await _pickImage();
                                if (picked != null) {
                                  setSheetState(() {
                                    tempProfileImage = picked;
                                  });
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: HexColor("#116754"),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 2),
                                ),
                                child: const Icon(Icons.camera_alt, size: 18, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: nameEditController,
                        decoration: InputDecoration(
                          labelText: 'Full Name',
                          prefixIcon: const Icon(Icons.person_outline),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _DownwardDropdownField(
                        label: 'Grade Level',
                        value: tempGrade,
                        items: gradeLevels,
                        arrowColor: HexColor("#116754"),
                        onChanged: (v) => setSheetState(() => tempGrade = v),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: Text(
                                'Cancel',
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () async {
                                if (nameEditController.text.trim().isEmpty) return;
                                setState(() {
                                  _nameController.text = nameEditController.text.trim();
                                  _selectedGradeLevel = tempGrade;
                                  _profileImage = tempProfileImage; // Apply the new image
                                });
                                try {
                                  await _saveProfileData();
                                  if (context.mounted) Navigator.pop(context);
                                } catch (e) {
                                  // Error handled in _saveProfileData with SnackBar
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: HexColor("#116754"),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                              child: const Text(
                                'Save',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );


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
      arrowColor: HexColor("#116754"),
    );
  }



  // ================= PROFILE TAB (New) =================
  Widget _buildProfileTab() {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Facebook-style Cover and Profile Picture Header
          Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              // Cover Photo Placeholder
              Container(
                height: 180,
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      HexColor("#116754"),
                      HexColor("#2a7925"),
                    ],
                  ),
                ),
                child: Center(
                  child: Opacity(
                    opacity: 0.1,
                    child: Image.asset(
                      'lib/pages/assets/LIME ASSETS/lime.png',
                      height: 120,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
              // Profile Picture
              Positioned(
                top: 110,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: CircleAvatar(
                    key: ValueKey(_profileImageUrl ?? _profileImageThumbnail),
                    radius: 65,
                    backgroundColor: Colors.grey[200],
                    backgroundImage: _profileImage != null
                        ? FileImage(_profileImage!)
                        : (_profileImageThumbnail != null 
                            ? MemoryImage(base64Decode(_profileImageThumbnail!))
                            : (_profileImageUrl != null ? NetworkImage(_profileImageUrl!) : null)) as ImageProvider?,
                    child: (_profileImage == null && _profileImageUrl == null && _profileImageThumbnail == null)
                        ? Icon(Icons.person, size: 65, color: HexColor("#116754"))
                        : null,
                  ),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 75), // Space for the overlapping avatar
          
          // Name and Subtitle
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                Text(
                  _nameController.text,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.merriweather(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: HexColor("#116754"),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "Student",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: HexColor("#116754"),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _selectedGradeLevel ?? '',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (_assignedSections.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    "Section: ${_assignedSections.join(', ')}",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                  ),
                ],
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Action Buttons (Facebook-style)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Center(
              child: SizedBox(
                width: 200,
                child: ElevatedButton.icon(
                  onPressed: _showEditProfileSheet,
                  icon: const Icon(Icons.edit, size: 18, color: Colors.white),
                  label: const Text('Edit Profile', style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: HexColor("#116754"),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ),

          ),

          const SizedBox(height: 24),
          const Divider(thickness: 8, color: Color(0xFFEEEEEE)),

          // Settings List
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              children: [
                _buildFacebookListTile(
                  icon: Icons.info_outline,
                  title: 'About LIME',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AboutPage())),
                ),
                _buildFacebookListTile(
                  icon: Icons.person_add,
                  title: 'Request Section',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RequestSectionPage())),
                ),
                _buildFacebookListTile(
                  icon: Icons.logout,
                  title: 'Logout',
                  onTap: _logout,
                ),
                _buildFacebookListTile(
                  icon: Icons.delete_forever,
                  title: 'Delete Account',
                  titleColor: Colors.redAccent,
                  onTap: _deleteAccount,
                ),
              ],
            ),
          ),

        ],
      ),
    );
  }

  Widget _buildFacebookListTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color? titleColor,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.black87, size: 20),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: titleColor ?? Colors.black87,
        ),
      ),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
      onTap: onTap,
    );
  }

  // ================= SIDEBAR CONTENT (Desktop only) =================
  Widget _buildSidebarContent(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => _selectedIndex = 5),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
            child: StreamBuilder<DocumentSnapshot>(
              stream: _firestore.collection('students').doc(_auth.currentUser?.uid).snapshots(),
              builder: (context, snapshot) {
                final data = snapshot.data?.data() as Map<String, dynamic>?;
                final name = data?['name'] as String? ?? _nameController.text;
                final imgUrl = data?['profileImageUrl'] as String?;
                final imgThumb = data?['profileImageThumbnail'] as String?;
                final imgPath = data?['profileImagePath'] as String?;

                return Column(
                  children: [
                    CircleAvatar(
                      radius: 38,
                      backgroundColor: Colors.white,
                      backgroundImage: imgThumb != null 
                          ? MemoryImage(base64Decode(imgThumb))
                          : (imgUrl != null 
                              ? NetworkImage(imgUrl) 
                              : (imgPath != null && File(imgPath).existsSync() 
                                  ? FileImage(File(imgPath)) 
                                  : null)) as ImageProvider?,
                      child: (imgUrl == null && imgThumb == null && (imgPath == null || !File(imgPath).existsSync()))
                          ? Icon(Icons.person, size: 40, color: HexColor("#116754"))
                          : null,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      name,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                );
              }
            ),
          ),
        ),
        const Divider(color: Colors.white24),
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              _menuItem(context, Icons.assignment, 'Subjects', 0, key: _navClassesKey),
              _menuItem(context, Icons.grade, 'Grades', 1, key: _navGradesKey),
              _menuItem(context, Icons.home, 'Home', 2, key: _navHomeKey),
              _menuItem(context, Icons.help_outline_rounded, 'Help', 3, key: _navHelpKey), // NEW
              _menuItem(context, Icons.mail_outlined, 'Inbox', 4, key: _navInboxKey),       // SHIFTED
              _menuItem(context, Icons.person_outline, 'Profile', 5, key: _navProfileKey),   // SHIFTED
            const Divider(color: Colors.white24),

            ],
          ),
        ),
      ],
    );
  }


  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(HexColor("#116754")),
          ),
        ),
      );
    }

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
                      color: HexColor("#116754"),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
                          onTap: () async {
                            final picked = await _pickImage();
                            if (picked != null) {
                              setState(() {
                                _profileImage = picked;
                              });
                            }
                          },
                          child: CircleAvatar(
                            radius: 48,
                            backgroundColor: Colors.grey[200],
                            backgroundImage: _profileImage != null
                                ? FileImage(_profileImage!)
                                : (_profileImageThumbnail != null 
                                    ? MemoryImage(base64Decode(_profileImageThumbnail!))
                                    : (_profileImageUrl != null ? NetworkImage(_profileImageUrl!) : null)) as ImageProvider?,
                            child: (_profileImage == null && _profileImageUrl == null && _profileImageThumbnail == null)
                                ? Icon(Icons.camera_alt, size: 30, color: HexColor("#116754"))
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
                            if (v != 'Teacher') _selectedTeacherType = null;
                            if (v != 'Student') {
                              _selectedGradeLevel = null;
                            }
                          }),
                        ),
                        const SizedBox(height: 16),
                        if (_selectedUserType == 'Teacher')
                          _buildDropdown(
                            label: 'Teacher Type',
                            value: _selectedTeacherType,
                            items: teacherTypes,
                            onChanged: (v) => setState(() => _selectedTeacherType = v),
                          ),
                        if (_selectedUserType == 'Teacher') const SizedBox(height: 16),
                        if (_selectedUserType == 'Student')
                          _buildDropdown(
                            label: 'Grade Level',
                            value: _selectedGradeLevel,
                            items: gradeLevels,
                            onChanged: (v) => setState(() => _selectedGradeLevel = v),
                          ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _submitDetails,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: HexColor("#116754"),
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

    // ================= MAIN DASHBOARD =================
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isMobile = width <= 600;
        final isDesktop = width > 900;

        return Scaffold(
          backgroundColor: Colors.grey[50],
          appBar: isMobile
              ? AppBar(
                  title: Text(_getAppBarTitle(), style: const TextStyle(fontWeight: FontWeight.bold)),
                  backgroundColor: HexColor("#116754"),
                  foregroundColor: Colors.white,
                  centerTitle: true,
                  elevation: 0,
                  actions: [
                    const ConnectivityIndicator(showText: false),
                    SizedBox(width: isMobile ? 4 : 8),
                  ],
                )
              : null,
          body: isMobile
              ? _buildContent(_selectedIndex)
              : Row(
                  children: [
                    Container(
                      width: isDesktop ? 280 : 240,
                      color: HexColor("#116754"),
                      child: _buildSidebarContent(context),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: _buildContent(_selectedIndex),
                      ),
                    ),
                  ],
                ),
          bottomNavigationBar: isMobile
              ? SafeArea(
                  child: NavigationBarTheme(
                  data: NavigationBarThemeData(
                    labelTextStyle: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return const TextStyle(color: Colors.white, fontWeight: FontWeight.bold);
                      }
                      return const TextStyle(color: Colors.white70);
                    }),
                    iconTheme: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return const IconThemeData(color: Colors.white);
                      }
                      return const IconThemeData(color: Colors.white70);
                    }),
                  ),
                  child: NavigationBar(
                    backgroundColor: HexColor("#116754"),
                    indicatorColor: Colors.white.withValues(alpha: 0.1),
                    selectedIndex: _selectedIndex,
                    onDestinationSelected: (index) => setState(() => _selectedIndex = index),
                    destinations: [
                      NavigationDestination(icon: Icon(Icons.assignment_outlined, key: _navClassesKey), label: 'Subjects'),
                      NavigationDestination(icon: Icon(Icons.grade_outlined, key: _navGradesKey), label: 'Grades'),
                      NavigationDestination(icon: Icon(Icons.home_outlined, key: _navHomeKey), label: 'Home'),
                      NavigationDestination(icon: Icon(Icons.help_outline_rounded, key: _navHelpKey), label: 'Help'),
                      NavigationDestination(icon: Icon(Icons.mail_outlined, key: _navInboxKey), label: 'Inbox'),
                      NavigationDestination(icon: Icon(Icons.person_outline, key: _navProfileKey), label: 'Profile'),
                    ],
                  ),
                ),
              )
              : null,
        );
      },
    );
  }

  Widget _menuItem(BuildContext context, IconData icon, String label, int index, {VoidCallback? onTap, GlobalKey? key}) {
    return ListTile(
      key: key,
      leading: Icon(icon, color: Colors.white),
      title: Text(label, style: const TextStyle(color: Colors.white)),
      selected: _selectedIndex == index,
      selectedTileColor: Colors.white.withValues(alpha: 0.2),
      onTap: onTap ?? () {
        setState(() => _selectedIndex = index);
      },
    );
  }

  Widget _buildContent(int index) {
    return _getPage(index);
  }

  String _getAppBarTitle() {
    switch (_selectedIndex) {
      case 0: return 'My Subjects';
      case 1: return 'My Grades';
      case 2: return 'LIME';
      case 3: return 'Help & Tutorials';
      case 4: return 'Inbox';
      case 5: return 'Profile';
      default: return 'LIME';
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