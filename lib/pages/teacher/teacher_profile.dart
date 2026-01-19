import 'dart:io';
import 'dart:async';
import 'dart:convert';
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

// Import the separate page files
import 'teacher_home_page.dart';
import 'teacher_inbox_page.dart';
import 'teacher_about_page.dart';
import 'my_classes_page.dart';
import 'teacher_schedule_page.dart';
import 'unassigned_students_page.dart';
import '../../widgets/delete_account_dialog.dart';
import '../../widgets/connectivity_indicator.dart';
import '../common/processing_deletion_page.dart';
import '../common/help_page.dart';
import '../../widgets/guide_pointer.dart';

class ProfileTeacherPage extends StatefulWidget {
  const ProfileTeacherPage({super.key});

  @override
  State<ProfileTeacherPage> createState() => _ProfileTeacherPageState();
}

class _ProfileTeacherPageState extends State<ProfileTeacherPage> {
  int _selectedIndex = 2; // Home is now at index 2 (Middle)
  bool _detailsSubmitted = false;
  bool _isLoading = true;
  bool _isLoadingProfile = false; // Guard for recursion
  StreamSubscription? _profileSubscription;
  Stream<List<DocumentSnapshot>>? _sectionsStream;
  final StreamController<List<DocumentSnapshot>> _sectionsStreamController = StreamController<List<DocumentSnapshot>>.broadcast();
  StreamSubscription? _adviserSub;
  StreamSubscription? _teacherSub;
  List<DocumentSnapshot> _adviserDocs = [];
  List<DocumentSnapshot> _teacherDocs = [];
  final List<Widget?> _pages = List.filled(6, null);

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _accessCodeController = TextEditingController();
  String? _selectedUserType;
  String? _selectedTeacherType;
  File? _profileImage;
  String? _profileImageUrl;
  String? _profileImageThumbnail;

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

  // Navigation Keys - Mobile (NavigationBar)
  final GlobalKey _navScheduleKey = GlobalKey();
  final GlobalKey _navClassesKey = GlobalKey();
  final GlobalKey _navInboxKey = GlobalKey();
  final GlobalKey _navProfileKey = GlobalKey();

  // Navigation Keys - Desktop (Sidebar)
  final GlobalKey _sidebarScheduleKey = GlobalKey();
  final GlobalKey _sidebarClassesKey = GlobalKey();
  final GlobalKey _sidebarInboxKey = GlobalKey();
  final GlobalKey _sidebarProfileKey = GlobalKey();
  
  final GlobalKey _profileTabContentKey = GlobalKey();
  
  final GlobalKey<TeacherHomePageState> _homePageKey = GlobalKey<TeacherHomePageState>();
  final GlobalKey<MyClassesPageState> _myClassesPageKey = GlobalKey<MyClassesPageState>();
  final GlobalKey<TeacherSchedulePageState> _schedulePageKey = GlobalKey<TeacherSchedulePageState>();
  final GlobalKey<TeacherInboxPageState> _inboxPageKey = GlobalKey<TeacherInboxPageState>();

  @override
  void initState() {
    super.initState();
    _sectionsStream = _sectionsStreamController.stream;
    _loadProfileData();
  }


  void _initSectionsStream() {
    final user = _auth.currentUser;
    if (user == null) return;

    _adviserSub?.cancel();
    _teacherSub?.cancel();

    // Query 1: Where I am the adviser
    _adviserSub = _firestore.collection('sections')
        .where('adviserUid', isEqualTo: user.uid)
        .snapshots()
        .listen((snap) {
      _adviserDocs = snap.docs;
      _emitMergedSections();
    });

    // Query 2: Where I am a subject teacher
    _teacherSub = _firestore.collection('sections')
        .where('teacherUids', arrayContains: user.uid)
        .snapshots()
        .listen((snap) {
      _teacherDocs = snap.docs;
      _emitMergedSections();
    });
  }

  void _emitMergedSections() {
    final unique = {for (var doc in [..._adviserDocs, ..._teacherDocs]) doc.id: doc};
    if (!_sectionsStreamController.isClosed) {
      _sectionsStreamController.add(unique.values.toList());
    }
  }

  Widget _getPage(int index) {
    if (_pages[index] != null) return _pages[index]!;

    switch (index) {
      case 0:
        _pages[index] = TeacherSchedulePage(
          key: _schedulePageKey,
          sectionsStream: _sectionsStream,
        );
        break;
      case 1:
        _pages[index] = MyClassesPage(
          key: _myClassesPageKey,
          sectionsStream: _sectionsStream,
        );
        break;
      case 2:
        _pages[index] = TeacherHomePage(
          key: _homePageKey,
          onNavigate: _onItemTapped,
          sectionsStream: _sectionsStream,
          // Pass mobile keys
          scheduleKey: _navScheduleKey,
          classesKey: _navClassesKey,
          inboxKey: _navInboxKey,
          profileKey: _navProfileKey,
          // Pass desktop keys
          sidebarScheduleKey: _sidebarScheduleKey,
          sidebarClassesKey: _sidebarClassesKey,
          sidebarInboxKey: _sidebarInboxKey,
          sidebarProfileKey: _sidebarProfileKey,
          // Optimized data sharing
          userName: _nameController.text,
          profileImageUrl: _profileImageUrl,
          profileImageThumbnail: _profileImageThumbnail,
          profileImagePath: _profileImage?.path,
          userStream: _firestore.collection('teachers').doc(_auth.currentUser?.uid).snapshots(),
        );
        break;
      case 3:
        _pages[index] = HelpPage(
          onStartTour: () {
            setState(() {
              _selectedIndex = 2; // Switch to Home
            });
            if (_pageController.hasClients) _pageController.jumpToPage(2);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _homePageKey.currentState?.startTour();
            });
          },
          onStartGradeTour: () {
            setState(() => _selectedIndex = 1);
            if (_pageController.hasClients) _pageController.jumpToPage(1);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _myClassesPageKey.currentState?.startGradeTour();
            });
          },
          onStartClassesTour: () {
            GuidePointer.dismiss();
            setState(() => _selectedIndex = 1);
            if (_pageController.hasClients) _pageController.jumpToPage(1);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _myClassesPageKey.currentState?.startClassesTour();
            });
          },
          userType: 'Teacher',
        );
        break;
      case 4:
        _pages[index] = TeacherInboxPage(key: _inboxPageKey);
        break;
      case 5:
        _pages[index] = _buildProfileTab();
        break;
    }
    return _pages[index]!;
  }

  void _updatePages() {
    // Re-create HelpPage with conditional callbacks
    final helpPage = HelpPage(
      onStartTour: () {
        setState(() {
          _selectedIndex = 2; // Switch to Home
        });
        
        if (_pageController.hasClients) {
          _pageController.jumpToPage(2);
        }
        
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _homePageKey.currentState?.startTour();
        });
      },
      onStartGradeTour: () {
         setState(() {
          _selectedIndex = 1; // Switch to Classes
        });
        
        if (_pageController.hasClients) {
          _pageController.jumpToPage(1);
        }
        
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _myClassesPageKey.currentState?.startGradeTour();
        });
      },
      // Restricted Tours - Only for Advisers
      onStartClassesTour: () {
        GuidePointer.dismiss();
        setState(() {
          _selectedIndex = 1; // My Classes
        });
        if (_pageController.hasClients) _pageController.jumpToPage(1);
        
        WidgetsBinding.instance.addPostFrameCallback((_) {
           _myClassesPageKey.currentState?.startClassesTour();
        });
      },

      onStartTeachersTour: () {
        GuidePointer.dismiss();
        setState(() {
          _selectedIndex = 1; // My Classes (Teachers tab)
        });
        if (_pageController.hasClients) _pageController.jumpToPage(1);
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Starting "How to Manage Teachers" tour...')),
        );
        
        WidgetsBinding.instance.addPostFrameCallback((_) {
           _myClassesPageKey.currentState?.startTeachersTour();
        });
      },
      
      onStartScheduleTour: () {
        GuidePointer.dismiss();
        setState(() {
          _selectedIndex = 0; // Schedule
        });
        if (_pageController.hasClients) _pageController.jumpToPage(0);

        WidgetsBinding.instance.addPostFrameCallback((_) {
          _schedulePageKey.currentState?.startScheduleTour();
        });
      },
      userType: 'Teacher',
    );

    setState(() {
      if (_pages.length > 3) {
        _pages[3] = helpPage;
      }
    });
  }

  final PageController _pageController = PageController(initialPage: 2);

  @override
  void dispose() {
    _profileSubscription?.cancel();
    _adviserSub?.cancel();
    _teacherSub?.cancel();
    _sectionsStreamController.close();
    _nameController.dispose();
    _accessCodeController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _onItemTapped(int index) {
    if (_selectedIndex == index) return;
    
    // Dismiss active tours and reset demo modes on tabs
    GuidePointer.dismiss();
    _schedulePageKey.currentState?.resetTour();
    _myClassesPageKey.currentState?.resetTour();

    setState(() {
      _selectedIndex = index;
    });

    // Animate to page (only for mobile if using PageView)
    if (_pageController.hasClients) {
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _onPageChanged(int index) {
    if (_selectedIndex != index) {
      GuidePointer.dismiss();
      _schedulePageKey.currentState?.resetTour();
      _myClassesPageKey.currentState?.resetTour();
    }
    
    setState(() {
      _selectedIndex = index;
    });
  }
  Future<void> _loadProfileData() async {
    final user = _auth.currentUser;
    if (user == null || _isLoadingProfile) {
      if (mounted && user == null) setState(() => _isLoading = false);
      return;
    }

    _isLoadingProfile = true;
    _profileSubscription?.cancel();

    try {
      // Determine which collection to listen to
      final teacherDoc = await _firestore.collection('teachers').doc(user.uid).get();
      final collectionName = teacherDoc.exists ? 'teachers' : 'students';
      final isActuallyTeacher = teacherDoc.exists;

      _isLoadingProfile = false; // Reset guard after initial collection check
      
      _profileSubscription = _firestore.collection(collectionName).doc(user.uid).snapshots().listen((doc) {
        if (!mounted) return;
        
        // If document moved collections (e.g. on another device), reload the whole listener
        if (!doc.exists) {
          // REMOVED recursive call that caused infinite loops on new accounts/Android.
          // The snapshot listener itself will fire again once the document is created.
          debugPrint('Profile document does not exist yet, waiting for creation...');
          return;
        }

        final data = doc.data()!;
        final name = data['name'] as String? ?? '';
        final userType = isActuallyTeacher ? 'Teacher' : data['userType'] as String?;
        final teacherType = data['teacherType'] as String?;
        final detailsSubmitted = data['detailsSubmitted'] as bool? ?? false;
        final imgPath = data['profileImagePath'] as String?;
        final imgUrl = data['profileImageUrl'] as String?;

        if (mounted) {
          setState(() {
            try {
              _nameController.text = name;
              _selectedUserType = userType;
              _selectedTeacherType = teacherType;
              _detailsSubmitted = detailsSubmitted;
              _profileImageUrl = imgUrl;
              _profileImageThumbnail = data['profileImageThumbnail'] as String?;

              if (imgPath != null && File(imgPath).existsSync()) {
                _profileImage = File(imgPath);
              } else {
                _profileImage = null; 
              }

              } finally {
                _isLoading = false;
                // Update pages configuration based on new role data
                _updatePages();
                _initSectionsStream(); // Refresh stream listeners
              }
          });
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
    } catch (e) {
      debugPrint('Error starting profile listener: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<String?> _generateThumbnail(File file) async {
    try {
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        // flutter_image_compress might not support desktop fully or requires specific setup.
        // For now, on Desktop, we might skip thumbnail or just read small file.
        // But let's try reading it and if it's small enough, use it directly?
        // Or just skip for now and rely on local path.
        // Actually, let's try to just return null for now to be safe on Desktop unless we validity it.
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
        final collection = (_selectedUserType == 'Teacher') ? 'teachers' : 'students';
        final docRef = _firestore.collection(collection).doc(user.uid);

        // Get existing data to preserve fields
        final snap = await docRef.get();
        final Map<String, dynamic> dataToSave = {
          'uid': user.uid,
          'name': _nameController.text,
          'email': user.email ?? '',
          'userType': _selectedUserType,
          'detailsSubmitted': true,
          'hasSeenWelcome': true,
        };

        if (_selectedTeacherType != null) {
          dataToSave['teacherType'] = _selectedTeacherType;
        }

        if (!snap.exists || (snap.data()?['createdAt'] == null)) {
          dataToSave['createdAt'] = FieldValue.serverTimestamp();
        }

        // Handle Image
        if (_profileImage != null) {
          dataToSave['profileImagePath'] = _profileImage!.path;
          
          // Generate thumbnail
          final thumbnail = await _generateThumbnail(_profileImage!);
          if (thumbnail != null) {
            dataToSave['profileImageThumbnail'] = thumbnail;
          }
        } else if (_profileImage == null && _profileImageUrl == null) {
           // Explicitly clear if both are null (removal) - though UI doesn't support removal yet
        }

        await docRef.set(dataToSave, SetOptions(merge: true));

        // Update Firebase Auth display name
        await user.updateDisplayName(_nameController.text);
        
        // Force reload user to get latest display name
        await user.reload(); 

        // IMPORTANT: If switching to 'Teacher', ensure we clean up any 'Student' doc
        if (_selectedUserType == 'Teacher') {
           try {
             final studentDoc = await _firestore.collection('students').doc(user.uid).get();
             if (studentDoc.exists) {
               await _firestore.collection('students').doc(user.uid).delete();
             }
           } catch (e) {
             debugPrint("Error cleaning up student doc: $e");
           }
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Profile updated successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        }

      } catch (e) {
        debugPrint('Error saving to Firestore: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error saving profile: $e'),
              backgroundColor: Colors.red,
            ),
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
      if (!mounted) return null;
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

      // Verify code against server-stored codes
      try {
        final firestore = _firestore;
        List<String> codes = [];

        final regDoc = await firestore.collection('config').doc('registration').get();
        var raw = regDoc.data()?['teacher_codes'];
        if (raw is List) {
          codes = raw.map((e) => e?.toString().trim() ?? '').where((s) => s.isNotEmpty).toList();
        }

        // Fallback: search all docs under 'config'
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

    try {
      await _saveProfileData();
    } catch (e) {
      // Error SnackBar already shown in _saveProfileData
      return;
    }
    
    if (!mounted) return;
    
    // If student, navigate to home (although this file is mostly for teacher, legacy accounts might start here)
    if (_selectedUserType == 'Student') {
       Navigator.pushReplacementNamed(context, '/home');
    } else {
       setState(() => _detailsSubmitted = true);
    }
  }

  // ================= DELETE ACCOUNT =================
  Future<void> _deleteAccount() async {
    final password = await showDeleteAccountDialog(context);
    
    if (password == null || password.isEmpty) return;
    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => ProcessingDeletionPage(password: password),
      ),
      (_) => false,
    );
  }

  // ================= LOGOUT =================
  Future<void> _logout() async {
    await _auth.signOut();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/signin', (_) => false);
  }

  void _showEditProfileSheet() {
    final TextEditingController nameEditController = TextEditingController(text: _nameController.text);
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
                child: Column(
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
                    StatefulBuilder(builder: (context, setSheetState) {
                      return Stack(
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
                      );
                    }),
                    const SizedBox(height: 24),
                    TextField(
                      controller: nameEditController,
                      decoration: InputDecoration(
                        labelText: 'Full Name',
                        prefixIcon: const Icon(Icons.person_outline),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey[300]!),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: HexColor("#116754"), width: 2),
                        ),
                      ),
                    ),
                  const SizedBox(height: 48),
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
                              // Save Logic
                              if (nameEditController.text.trim().isEmpty) return;
                              setState(() {
                                _nameController.text = nameEditController.text.trim();
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
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
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
                ),
              ),
            ),
          ),
        ),
      ),
    );


  }


  // ================= HELPERS & WIDGETS =================
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
      onChanged: onChanged,
      arrowColor: HexColor("#116754"),
    );
  }

  Widget _buildProfileTab() { // Removed BuildContext context parameter
    return SingleChildScrollView(
      key: _profileTabContentKey,
      child: Column(
        children: [
          // Facebook-style Cover and Profile Picture Header
          // Facebook-style Cover and Profile Picture Header
          StreamBuilder<DocumentSnapshot>(
            stream: _firestore.collection('teachers').doc(_auth.currentUser?.uid).snapshots(),
            builder: (context, snapshot) {
               final data = snapshot.data?.data() as Map<String, dynamic>?;
               final name = data?['name'] as String? ?? '';
               final teacherType = data?['teacherType'] as String? ?? 'Teacher';
               final imgUrl = data?['profileImageUrl'] as String?;
               final imgThumb = data?['profileImageThumbnail'] as String?;

               return Column(
                 children: [
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
                              radius: 65,
                              backgroundColor: Colors.grey[200],
                              // Prioritize local file if just picked, otherwise stream data
                              backgroundImage: _profileImage != null
                                  ? FileImage(_profileImage!)
                                  : (imgThumb != null 
                                      ? MemoryImage(base64Decode(imgThumb))
                                      : (imgUrl != null ? NetworkImage(imgUrl) : null)) as ImageProvider?,
                              child: (_profileImage == null && imgUrl == null && imgThumb == null)
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
                            name.isNotEmpty ? name : _nameController.text, // Fallback to controller if stream empty initially
                            textAlign: TextAlign.center,
                            style: GoogleFonts.merriweather(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: HexColor("#116754"),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            teacherType.isNotEmpty ? teacherType : (_selectedTeacherType ?? 'Teacher'),
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                 ],
               );
            }
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
                if (_selectedTeacherType == 'Adviser')
                  _buildFacebookListTile(
                    icon: Icons.person_add_outlined,
                    title: 'Unassigned Students',
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UnassignedStudentsPage())),
                  ),
                _buildFacebookListTile(
                  icon: Icons.info_outline,
                  title: 'About LIME',
                  onTap: () async {
                    final result = await Navigator.push<String>(
                      context, 
                      MaterialPageRoute(builder: (_) => const TeacherAboutPage()),
                    );
                    if (result != null && mounted) {
                      // Handle tour selection - navigate to appropriate tab and trigger tour
                      if (result == 'classes_tour') {
                        _onItemTapped(1); // Go to Classes tab
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _myClassesPageKey.currentState?.startClassesTour();
                        });
                      } else if (result == 'grades_tour') {
                        _onItemTapped(1); // Go to Classes tab for grades demo
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _myClassesPageKey.currentState?.startGradeTour();
                        });
                      } else if (result == 'inbox_tour') {
                        // SPOTLIGHT the Inbox tab first, then navigate
                        final bool isDesktop = MediaQuery.of(context).size.width > 900;
                        final targetKey = isDesktop ? _sidebarInboxKey : _navInboxKey;

                        GuidePointer.show(
                          context,
                          steps: [
                            GuideStep(
                              targetKey: targetKey,
                              title: "Step 1: Inbox Tab",
                              content: "Tap here to access your Inbox. You can send announcements and messages to students.",
                              buttonLabel: "Go to Inbox",
                            ),
                          ],
                          onComplete: () {
                            _onItemTapped(4); // Navigate to Inbox after spotlight
                          },
                        );
                      } else if (result == 'schedule_tour') {
                        // Navigate to Schedule tab first
                        _onItemTapped(0);
                        
                        // Then show spotlight and load demo data
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _schedulePageKey.currentState?.startScheduleTour();
                          
                          final bool isDesktop = MediaQuery.of(context).size.width > 900;
                          final targetKey = isDesktop ? _sidebarScheduleKey : _navScheduleKey;

                          GuidePointer.show(
                            context,
                            steps: [
                              GuideStep(
                                targetKey: targetKey,
                                title: "Your Teaching Schedule",
                                content: "This is your weekly timetable showing all your classes, sections, and times. Each card shows a subject you teach.",
                                buttonLabel: "Got it!",
                              ),
                            ],
                            onComplete: () {},
                          );
                        });
                      }
                    }
                  },
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.black87, size: 22),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w500,
          color: titleColor ?? Colors.black87,
        ),
      ),
      trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey),
      onTap: onTap,
    );
  }

  Widget _buildSidebarContent(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: () => _onItemTapped(5),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
            child: StreamBuilder<DocumentSnapshot>(
              stream: _firestore.collection('teachers').doc(_auth.currentUser?.uid).snapshots(),
              builder: (context, snapshot) {
                final data = snapshot.data?.data() as Map<String, dynamic>?;
                final name = data?['name'] as String? ?? 'Teacher';
                final teacherType = data?['teacherType'] as String? ?? '';
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
                    const SizedBox(height: 4),
                    Text(
                      teacherType,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
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
              _menuItem(context, Icons.schedule, 'My Schedule', 0, key: _sidebarScheduleKey),
              _menuItem(context, Icons.class_, 'My Classes', 1, key: _sidebarClassesKey),
              _menuItem(context, Icons.home, 'Home', 2),
              _menuItem(context, Icons.help_outline, 'Help', 3), // NEW
              _menuItem(context, Icons.person, 'Profile', 5, key: _sidebarProfileKey),   // SHIFTED
              
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
                    context,
                    Icons.inbox, 
                    'Inbox', 
                    4,
                    key: _sidebarInboxKey,
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
              
              const Divider(color: Colors.white24),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _menuItem(BuildContext context, IconData icon, String label, int index,
      {VoidCallback? onTap, Widget? trailing, Key? key}) {
    return ListTile(
      key: key,
      leading: Icon(icon, color: Colors.white),
      title: Text(label, style: const TextStyle(color: Colors.white)),
      trailing: trailing,
      selected: _selectedIndex == index,
      selectedTileColor: Colors.white.withValues(alpha: 0.2),
      onTap: onTap ?? () {
        setState(() => _selectedIndex = index);
      },
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
                valueColor: AlwaysStoppedAnimation<Color>(HexColor("#116754")),
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
                                if (v != 'Teacher') {
                                  _selectedTeacherType = null;
                                }
                              }),
                            ),
                            const SizedBox(height: 16),
                            if (_selectedUserType == 'Teacher') ...[
                              _buildDropdown(
                                label: 'Teacher Type',
                                value: _selectedTeacherType,
                                items: teacherTypes,
                                onChanged: (v) => setState(() => _selectedTeacherType = v),
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

        // ================= DASHBOARD =================
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
              ? PageView(
                  physics: const NeverScrollableScrollPhysics(), // Disable swipe
                  controller: _pageController,
                  onPageChanged: _onPageChanged,
                  children: List.generate(6, (i) => _getPage(i)),
                )
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
                    onDestinationSelected: _onItemTapped,
                    destinations: [
                      NavigationDestination(icon: Icon(Icons.schedule_outlined, key: _navScheduleKey), label: 'Schedule'), // Index 0
                      NavigationDestination(icon: Icon(Icons.class_outlined, key: _navClassesKey), label: 'Classes'),   // Index 1
                      const NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),       // Index 2
                      const NavigationDestination(icon: Icon(Icons.help_outline_rounded), label: 'Help'), // Index 3
                      NavigationDestination(icon: Icon(Icons.mail_outlined, key: _navInboxKey), label: 'Inbox'),      // Index 4
                      NavigationDestination(icon: Icon(Icons.person_outline, key: _navProfileKey), label: 'Profile'),   // Index 5
                    ],
                  ),
                ),
              )
              : null,
        );
      },
    );
  }

  // Helper for Desktop switching (Mobile uses PageView children list directly)
  Widget _buildContent(int index) {
    return _getPage(index);
  }

  String _getAppBarTitle() {
    switch (_selectedIndex) {
      case 0: return 'My Schedule';
      case 1: return 'My Classes';
      case 2: return 'LIME'; // Home
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
