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
import 'dart:typed_data';

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
import '../../utils/notification_helper.dart';
import '../../widgets/change_password_dialog.dart';
import '../../widgets/guide_pointer.dart';

class ProfileStudentPage extends StatefulWidget {
  const ProfileStudentPage({super.key});

  @override
  State<ProfileStudentPage> createState() => _ProfileStudentPageState();
}

class _ProfileStudentPageState extends State<ProfileStudentPage> {
  int _selectedIndex = 2; // Default to Home
  bool _detailsSubmitted = false;
  bool _isLoading = true;
  bool _isLoadingProfile = false;
  StreamSubscription? _profileSubscription;
  
  // SHARED DATA LAYER
  StreamSubscription? _sectionsSub;
  StreamSubscription? _notificationSub;
  QuerySnapshot? _sectionsSnapshot;
  Map<String, dynamic>? _currentProfileData;
  List<String> _currentListeningSectionIds = [];

  final TextEditingController _nameController = TextEditingController();
  String? _selectedUserType;
  String? _selectedTeacherType;
  String? _selectedGradeLevel;
  File? _profileImage;
  String? _profileImageUrl;
  String? _profileImageThumbnail;
  List<String> _assignedSections = [];
  final List<Widget?> _pages = List.filled(6, null);
  Uint8List? _thumbnailBytes;
  int? _pendingInitialTab;

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

  // Navigation Keys - Mobile (Bottom Nav)
  final GlobalKey _navScheduleKey = GlobalKey();
  final GlobalKey _navClassesKey = GlobalKey();
  final GlobalKey _navGradesKey = GlobalKey();
  final GlobalKey _navProfileKey = GlobalKey();
  final GlobalKey _navHelpKey = GlobalKey();
  final GlobalKey _navHomeKey = GlobalKey();

  // Navigation Keys - Desktop (Sidebar)
  final GlobalKey _sidebarClassesKey = GlobalKey();
  final GlobalKey _sidebarGradesKey = GlobalKey();
  final GlobalKey _sidebarInboxKey = GlobalKey();
  final GlobalKey _sidebarProfileKey = GlobalKey();
  final GlobalKey _sidebarHelpKey = GlobalKey();
  final GlobalKey _sidebarHomeKey = GlobalKey();

  final GlobalKey _statsOverviewKey = GlobalKey(); // Centrally managed key

  @override
  void initState() {
    super.initState();
    _loadProfileData();
    _initNotificationListener();
    // Safety timeout to prevent infinite spinner
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _isLoading) {
        setState(() => _isLoading = false);
      }
    });
    // _initSectionsStream(); // REMOVED
  }

  @override
  void dispose() {
    _profileSubscription?.cancel();
    _sectionsSub?.cancel();
    _notificationSub?.cancel();
    _nameController.dispose();
    super.dispose();
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
                // Show pop-out toast globally for NEW notifications
                NotificationHelper.showInfo(context, data['body'] ?? data['title'] ?? 'New Notification');
                // Removed auto-read logic so badge remains visible
                // change.doc.reference.update({'read': true});
              }
            }
          }
        });
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
          _currentProfileData = data;
          
          final name = data['name'] as String? ?? '';
          final sections = data['sections'] as List<dynamic>?;
          final sectionsList = sections != null ? sections.map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).toList() : <String>[];
          
          setState(() {
            _nameController.text = name;
            _selectedUserType = data['userType'] as String?;
            _selectedTeacherType = data['teacherType'] as String?;
            _selectedGradeLevel = data['gradeLevel'] as String?;
            _detailsSubmitted = data['detailsSubmitted'] as bool? ?? false;
            _assignedSections = sectionsList;
            _profileImageUrl = data['profileImageUrl'] as String?;
            _profileImageThumbnail = data['profileImageThumbnail'] as String?;
            if (_profileImageThumbnail != null) {
              _thumbnailBytes = base64Decode(_profileImageThumbnail!);
            } else {
              _thumbnailBytes = null;
            }

            if (data['profileImagePath'] != null && File(data['profileImagePath'] as String).existsSync()) {
              _profileImage = File(data['profileImagePath'] as String);
            } else {
              _profileImage = null; 
            }
            // Force re-creation of all pages to reflect updated profile info
            _pages.fillRange(0, _pages.length, null);
          });

          // Start listener for sections
          _updateSectionsSubscription(sectionsList);
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
      if (mounted) setState(() => _isLoading = false);
    });
  }

  void _updateSectionsSubscription(List<String> sectionIds) {
    // Only resubscribe if list changed from what we are currently listening to
    if (_areListsEqual(_currentListeningSectionIds, sectionIds) && _sectionsSub != null) return;
    _currentListeningSectionIds = List.from(sectionIds);
    
    _sectionsSub?.cancel();
    if (sectionIds.isEmpty) {
      setState(() => _sectionsSnapshot = null);
      return;
    }

    final idsToQuery = sectionIds.take(10).toList(); // Firestore whereIn limit
    _sectionsSub = _firestore.collection('sections')
        .where(FieldPath.documentId, whereIn: idsToQuery)
        .snapshots()
        .listen((snap) {
          if (mounted) {
            setState(() => _sectionsSnapshot = snap);
          }
        });
  }

  bool _areListsEqual(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
        if (a[i] != b[i]) return false;
    }
    return true;
  }

  Widget _getPage(int index) {
    if (_pages[index] != null) return _pages[index]!;
    
    switch (index) {
      case 0:
        _pages[index] = SubjectsPage(
          initialSectionsSnapshot: _sectionsSnapshot,
          initialTabIndex: _pendingInitialTab,
        );
        _pendingInitialTab = null;
        break;
      case 1:
        _pages[index] = GradesPage(
          initialData: _currentProfileData,
          initialSectionsSnapshot: _sectionsSnapshot,
          initialSemester: _pendingInitialTab,
        );
        _pendingInitialTab = null;
        break;
      case 2:
        _pages[index] = HomePage(
          onNavigate: (i, {initialTab}) => setState(() {
            _selectedIndex = i;
            if (initialTab != null) {
              _pendingInitialTab = initialTab;
              _pages[i] = null; // Force re-creation
            }
          }),
          scheduleKey: _navScheduleKey,
          classesKey: _navClassesKey,
          gradesKey: _navGradesKey,
          profileKey: _navProfileKey,
          helpKey: _navHelpKey,
          statsOverviewKey: _statsOverviewKey, // NEW
          profileImagePath: _profileImage?.path,
          profileImageThumbnail: _profileImageThumbnail,
          profileImageUrl: _profileImageUrl,
          profileThumbnailBytes: _thumbnailBytes,
        );
        break;
      case 3:
        _pages[index] = HelpPage(
          onStartTour: () {
            setState(() {
              _selectedIndex = 2; // Switch to Home
            });
            
            // Wait for Home page to load before starting tour
            Future.delayed(const Duration(seconds: 1), () {
              if (mounted) {
                _startStudentTour();
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

  // ================= SAVE PROFILE =================
  Future<String?> _generateThumbnail(File file) async {
    try {
      // Desktop (Windows/Linux/Mac): Read bytes directly since compression plugin is mobile-only
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        final bytes = await file.readAsBytes();
        // Limit to ~500KB to avoid Firestore document limit (1MB)
        if (bytes.length > 500 * 1024) {
          debugPrint("Image too large for Firestore thumbnail: ${bytes.length} bytes");
          return null; // Or implement a pure-Dart resizing/compression here if needed
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
      /* } else {
        return selectedFile;
      } */
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

  // ================= CHANGE PASSWORD =================
  void _changePassword() {
    showDialog(
      context: context,
      builder: (context) => const ChangePasswordDialog(),
    );
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
                                  _profileImage = tempProfileImage;

                                  // NEW: Instant local thumbnail preview for global syncing
                                  if (_profileImage != null) {
                                    _thumbnailBytes = _profileImage!.readAsBytesSync();
                                  }

                                  // IMMEDIATE LOCAL PREVIEW:
                                  // Force all pages to re-render with new local data
                                  _pages.fillRange(0, _pages.length, null);
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
                    color: Colors.black,
                    shape: BoxShape.circle,
                  ),
                  child: CircleAvatar(
                    key: ValueKey("${_profileImageUrl ?? _profileImageThumbnail}_${_thumbnailBytes?.length ?? 0}_${_profileImage?.path}"),
                    radius: 65,
                    backgroundColor: Colors.grey[200],
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
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: (titleColor ?? HexColor("#116754")).withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: titleColor ?? HexColor("#116754"), size: 20),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: titleColor ?? Colors.black87,
          ),
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }

  // ================= SIDEBAR CONTENT (Desktop only) =================
  Widget _buildSidebarContent(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => _selectedIndex = 4),
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
                  _nameController.text.isNotEmpty ? _nameController.text : 'Student',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold),
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
              _menuItem(context, Icons.assignment, 'Subjects', 0, key: _sidebarClassesKey),
              _menuItem(context, Icons.grade, 'Grades', 1, key: _sidebarGradesKey),
              _menuItem(context, Icons.home, 'Home', 2, key: _sidebarHomeKey),
              _menuItem(context, Icons.help_outline_rounded, 'Help', 3, key: _sidebarHelpKey),
              _menuItem(context, Icons.mail_outline, 'Inbox', 4, key: _sidebarInboxKey),
              _menuItem(context, Icons.person_outline, 'Profile', 5, key: _sidebarProfileKey),
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
                    selectedIndex: _selectedIndex == 5 ? 4 : (_selectedIndex == 4 ? 2 : _selectedIndex),
                    onDestinationSelected: (index) {
                      setState(() {
                         if (index == 4) {
                           _selectedIndex = 5; // Profile
                         } else {
                           _selectedIndex = index;
                         }
                      });
                    },
                    destinations: [
                      NavigationDestination(key: _navClassesKey, icon: const Icon(Icons.assignment_outlined), label: 'Subjects'),
                      NavigationDestination(key: _navGradesKey, icon: const Icon(Icons.grade_outlined), label: 'Grades'),
                      NavigationDestination(key: _navHomeKey, icon: const Icon(Icons.home_outlined), label: 'Home'),
                      NavigationDestination(key: _navHelpKey, icon: const Icon(Icons.help_outline_rounded), label: 'Help'),
                      NavigationDestination(key: _navProfileKey, icon: const Icon(Icons.person_outline), label: 'Profile'),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: ListTile(
        key: key,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        leading: Icon(icon, color: Colors.white),
        title: Text(label, style: const TextStyle(color: Colors.white)),
        selected: _selectedIndex == index,
        selectedTileColor: Colors.white.withValues(alpha: 0.2),
        onTap: onTap ?? () {
          setState(() {
            _selectedIndex = index;
            _pendingInitialTab = null; // Clear if navigating manually
          });
        },
      ),
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
      case 4: return 'Profile';
      default: return 'LIME';
    }
  }

  void _startStudentTour() {
    debugPrint('GUIDE: ProfileStudentPage._startStudentTour() called');
    final bool isDesktop = MediaQuery.of(context).size.width > 900;

    GuidePointer.show(
      context,
      steps: [
        GuideStep(
           targetKey: _statsOverviewKey,
           title: "Academic Performance",
           content: "Monitor your enrolled subjects, daily schedule, GPA transitions, and unread communications at a glance.",
        ),
        GuideStep(
          targetKey: isDesktop ? _sidebarClassesKey : _navClassesKey,
          title: "My Subjects",
          content: "Access your enrolled subjects and grades from this tab.",
          buttonLabel: "Next",
        ),
        GuideStep(
          targetKey: isDesktop ? _sidebarGradesKey : _navGradesKey,
          title: "Grades Overview",
          content: "Track your academic progress and see your latest marks here.",
          buttonLabel: "Next",
        ),
        GuideStep(
          targetKey: isDesktop ? _sidebarHelpKey : _navHelpKey,
          title: "Help & Tutorials",
          content: "Need guidance? Access all interactive tutorials and app information right here.",
          buttonLabel: "Next",
        ),
        GuideStep(
          targetKey: isDesktop ? _sidebarProfileKey : _navProfileKey,
          title: "Your Profile",
          content: "Manage your account, update your photo, and request new sections for your subjects.",
          buttonLabel: "Finish Tour",
        ),
      ],
      totalStepsOverride: 5,
      onComplete: () {},
    );
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