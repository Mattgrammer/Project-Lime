import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
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
import '../../utils/notification_helper.dart';
import '../../widgets/guide_pointer.dart';
import '../../widgets/change_password_dialog.dart';

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
  StreamSubscription? _notificationSub;
  final List<Widget?> _pages = List.filled(6, null);

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _accessCodeController = TextEditingController();
  String? _selectedUserType;
  String? _selectedTeacherType;
  File? _profileImage;
  String? _profileImageUrl;
  String? _profileImageThumbnail;
  Uint8List? _thumbnailBytes;
  List<String> _advisorySections = [];

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
    _loadProfileData();
    _initNotificationListener();
  }


  Widget _getPage(int index) {
    if (_pages[index] != null) return _pages[index]!;


    switch (index) {
      case 0:
        _pages[index] = TeacherSchedulePage(
          key: _schedulePageKey,
          // sectionsStream: null - let page create its own listener
        );
        break;
      case 1:
        _pages[index] = MyClassesPage(
          key: _myClassesPageKey,
          // sectionsStream: null - let page create its own listener
        );
        break;
      case 2:
        _pages[index] = TeacherHomePage(
          key: _homePageKey,
          onNavigate: (i, {initialTab}) => _onItemTapped(i, initialTab: initialTab),
          // sectionsStream: null - let page create its own listener
          // Pass mobile keys
          scheduleKey: _navScheduleKey,
          classesKey: _navClassesKey,
          profileKey: _navProfileKey,
          // Pass desktop keys
          sidebarScheduleKey: _sidebarScheduleKey,
          sidebarClassesKey: _sidebarClassesKey,
          sidebarProfileKey: _sidebarProfileKey,
          // Optimized data sharing
          userName: _nameController.text,
          profileImagePath: _profileImage?.path,
          teacherType: _selectedTeacherType,
          profileThumbnailBytes: _thumbnailBytes,
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
          onStartClassesTour: _selectedTeacherType == 'Subject Teacher' ? null : () {
            GuidePointer.dismiss();
            setState(() => _selectedIndex = 1);
            if (_pageController.hasClients) _pageController.jumpToPage(1);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _myClassesPageKey.currentState?.startClassesTour();
            });
          },
          onStartTeachersTour: _selectedTeacherType == 'Subject Teacher' ? null : () {
            GuidePointer.dismiss();
            setState(() => _selectedIndex = 1);
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
            setState(() => _selectedIndex = 0);
            if (_pageController.hasClients) _pageController.jumpToPage(0);

            WidgetsBinding.instance.addPostFrameCallback((_) {
              _schedulePageKey.currentState?.startScheduleTour();
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
      onStartClassesTour: _selectedTeacherType == 'Subject Teacher' ? null : () {
        GuidePointer.dismiss();
        setState(() {
          _selectedIndex = 1; // My Classes
        });
        if (_pageController.hasClients) _pageController.jumpToPage(1);
        
        WidgetsBinding.instance.addPostFrameCallback((_) {
           _myClassesPageKey.currentState?.startClassesTour();
        });
      },

      onStartTeachersTour: _selectedTeacherType == 'Subject Teacher' ? null : () {
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
      onStartInboxTour: () {
        GuidePointer.dismiss();
        setState(() {
          _selectedIndex = 4; // Inbox
        });
        if (_pageController.hasClients) _pageController.jumpToPage(4);

        WidgetsBinding.instance.addPostFrameCallback((_) {
          _inboxPageKey.currentState?.startInboxTour();
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
    _notificationSub?.cancel();
    _nameController.dispose();
    _accessCodeController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _onItemTapped(int index, {int? initialTab}) {
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
  void _initNotificationListener() {
    final user = _auth.currentUser;
    if (user == null) return;

    bool isFirstLoad = true;
    _notificationSub?.cancel();
    _notificationSub = _firestore
        .collection('notifications')
        .where('to', isEqualTo: user.uid)
        .where('read', isEqualTo: false)
        .snapshots()
        .listen((snap) {
          if (!mounted) return;
          
          if (isFirstLoad) {
            isFirstLoad = false;
            return;
          }

          for (var change in snap.docChanges) {
            if (change.type == DocumentChangeType.added) {
              final data = change.doc.data();
              if (data != null) {
                // Show pop-out toast globally
                NotificationHelper.showInfo(context, data['body'] ?? data['title'] ?? 'New Notification');
                // Mark as read immediately - Removed to allow user to see unread badge
                // change.doc.reference.update({'read': true});
              }
            }
          }
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
              if (_profileImageThumbnail != null) {
                _thumbnailBytes = base64Decode(_profileImageThumbnail!);
              } else {
                _thumbnailBytes = null;
              }

              if (imgPath != null && File(imgPath).existsSync()) {
                _profileImage = File(imgPath);
              } else {
                _profileImage = null; 
              }

              } finally {
                _isLoading = false;
                // Force all pages to rebuild with new profile data by clearing cache
                _pages.fillRange(0, _pages.length, null);
                // Update pages configuration based on new role data
                _updatePages();
              }
          });
        }
      }, onError: (e) {
        debugPrint('Error listening to profile: $e');
        if (mounted) setState(() => _isLoading = false);
      });

      // Also fetch advisory sections
      final sectionsSnap = await _firestore.collection('sections')
          .where('adviserUid', isEqualTo: user.uid)
          .get();
      if (mounted) {
        setState(() {
          _advisorySections = sectionsSnap.docs.map((d) => d.id).toList()..sort();
        });
      }
    } catch (e) {
      debugPrint('Error starting profile listener: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<String?> _generateThumbnail(File file) async {
    try {
      // Desktop (Windows/Linux/Mac): Read bytes directly since compression plugin is mobile-only
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        final bytes = await file.readAsBytes();
        // Limit to ~500KB to avoid Firestore document limit (1MB)
        if (bytes.length > 500 * 1024) {
          debugPrint("Image too large for Firestore thumbnail: ${bytes.length} bytes");
          return null; 
        }
        return base64Encode(bytes);
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

      // Skip cropping on Desktop (not fully supported by plugin)
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        return selectedFile;
      }
      
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
          ),
        ],
      );
      
      if (croppedFile != null) {
        return File(croppedFile.path);
      }
    }
    return selectedFile;
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

  // ================= CHANGE PASSWORD =================
  void _changePassword() {
    showDialog(
      context: context,
      builder: (context) => const ChangePasswordDialog(),
    );
  }

  void _showEditProfileSheet() {
    final TextEditingController nameEditController = TextEditingController(text: _nameController.text);
    String? tempTeacherType = _selectedTeacherType;
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
                                : (_thumbnailBytes != null
                                    ? MemoryImage(_thumbnailBytes!)
                                    : (_profileImageThumbnail != null
                                        ? MemoryImage(base64Decode(_profileImageThumbnail!))
                                        : (_profileImageUrl != null
                                            ? NetworkImage(_profileImageUrl!)
                                            : null))) as ImageProvider?,
                            child: (tempProfileImage == null && _thumbnailBytes == null && _profileImageThumbnail == null && _profileImageUrl == null)
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
                                  border: Border.all(color: Colors.black, width: 2),
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
                                  _selectedTeacherType = tempTeacherType;
                                  _profileImage = tempProfileImage;
                                  
                                  // NEW: Instant local thumbnail preview for global syncing
                                  if (_profileImage != null) {
                                    _thumbnailBytes = _profileImage!.readAsBytesSync();
                                  }

                                  // IMMEDIATE LOCAL PREVIEW:
                                  _pages.fillRange(0, _pages.length, null);
                                });
                                try {
                                  await _saveProfileData();
                                  if (context.mounted) Navigator.pop(context);
                                } catch (e) {
                                  // Error handled
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
          Column(
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
                        color: Colors.black,
                        shape: BoxShape.circle,
                      ),
                      child: CircleAvatar(
                        key: ValueKey("${_profileImageUrl ?? _profileImageThumbnail}_${_thumbnailBytes?.length ?? 0}_${_profileImage?.path}"),
                        radius: 65,
                        backgroundColor: Colors.grey[200],
                        // Prioritize local file if just picked, otherwise stream data
                        backgroundImage: _profileImage != null
                            ? FileImage(_profileImage!)
                            : (_thumbnailBytes != null 
                                ? MemoryImage(_thumbnailBytes!)
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
                      _nameController.text.isNotEmpty ? _nameController.text : 'Name', 
                      textAlign: TextAlign.center,
                      style: GoogleFonts.merriweather(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: HexColor("#116754"),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _selectedTeacherType ?? 'Teacher',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (_advisorySections.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: _advisorySections.map((s) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: HexColor("#116754"),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            s,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        )).toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ],
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
                  icon: Icons.lock_outline,
                  title: 'Change Password',
                  onTap: _changePassword,
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
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (titleColor ?? HexColor("#116754")),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: (titleColor ?? HexColor("#116754")).withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: titleColor ?? HexColor("#116754"), size: 22),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: titleColor ?? Colors.black87,
          ),
        ),
        trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }

  Widget _buildSidebarContent(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: () => _onItemTapped(4),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
            child: Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.black, width: 2.0),
                  ),
                  child: CircleAvatar(
                    radius: 38,
                    backgroundColor: Colors.white,
                    backgroundImage: _thumbnailBytes != null 
                        ? MemoryImage(_thumbnailBytes!)
                        : (_profileImageUrl != null 
                            ? NetworkImage(_profileImageUrl!) 
                            : (_profileImage != null && _profileImage!.existsSync() 
                                ? FileImage(_profileImage!) 
                                : null)) as ImageProvider?,
                    child: (_profileImageUrl == null && _profileImageThumbnail == null && (_profileImage == null || !_profileImage!.existsSync()))
                        ? Icon(Icons.person, size: 40, color: HexColor("#116754"))
                        : null,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  _nameController.text.isNotEmpty ? _nameController.text : 'Teacher',
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
        ),
        const Divider(color: Colors.white24),
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              _menuItem(context, Icons.schedule, 'My Schedule', 0, key: _sidebarScheduleKey),
              _menuItem(context, Icons.class_, 'My Classes', 1, key: _sidebarClassesKey),
              _menuItem(context, Icons.home, 'Home', 2),
              _menuItem(context, Icons.help_outline, 'Help', 3),
              _menuItem(context, Icons.mail_outline, 'Inbox', 4, key: _sidebarInboxKey),
              _menuItem(context, Icons.person, 'Profile', 5, key: _sidebarProfileKey),
              
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: ListTile(
        key: key,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        leading: Icon(icon, color: Colors.white),
        title: Text(label, style: const TextStyle(color: Colors.white)),
        trailing: trailing,
        selected: _selectedIndex == index,
        selectedTileColor: Colors.white.withValues(alpha: 0.2),
        onTap: onTap ?? () {
          setState(() => _selectedIndex = index);
        },
      ),
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
                    selectedIndex: _selectedIndex == 5 ? 4 : (_selectedIndex == 4 ? 2 : _selectedIndex), // Map Profile(5) to 4, Inbox(4) to Home(2) or keep selected? 
                    onDestinationSelected: (index) {
                      if (index == 4) {
                        // Profile tapped on mobile
                        _onItemTapped(5);
                      } else {
                        _onItemTapped(index);
                      }
                    },
                    destinations: [
                      NavigationDestination(key: _navScheduleKey, icon: const Icon(Icons.schedule_outlined), label: 'Schedule'), // Index 0
                      NavigationDestination(key: _navClassesKey, icon: const Icon(Icons.class_outlined), label: 'Classes'),   // Index 1
                      const NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),       // Index 2
                      const NavigationDestination(icon: Icon(Icons.help_outline_rounded), label: 'Help'), // Index 3
                      NavigationDestination(key: _navProfileKey, icon: const Icon(Icons.person_outline), label: 'Profile'),   // Index 4
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
      case 4: return 'Profile';
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
