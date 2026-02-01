import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:hexcolor/hexcolor.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:lime/pages/teacher/section_detail_page.dart';
import 'package:lime/widgets/lime_dropdown.dart';

class MyClassesPage extends StatefulWidget {
  final Stream<List<DocumentSnapshot>>? sectionsStream;
  const MyClassesPage({super.key, this.sectionsStream});

  @override
  State<MyClassesPage> createState() => MyClassesPageState();
}

class MyClassesPageState extends State<MyClassesPage> {
  StreamSubscription? _teacherSubscription;
  StreamSubscription? _sectionsSubscription;
  List<String> _sections = [];
  List<String> _ownedSections = [];
  bool _isLoading = true;
  String? _teacherType;
  String? _teacherName;
  Map<String, String?> _sectionThumbnails = {};
  
  // Tour Keys
  final GlobalKey _firstSectionKey = GlobalKey();
  final GlobalKey _createButtonKey = GlobalKey();
  
  bool _isGradeTourActive = false;
  bool _isDemoMode = false;

  @override
  void initState() {
    super.initState();
    _listenToData();
  }
  
  void startGradeTour() {
    setState(() {
      _isGradeTourActive = true;
    });

    // Directly open the Demo Class experience for everyone
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const SectionDetailPage(
          sectionName: "[TUTORIAL] Demo Class",
          startGradeTour: true,
        ),
      ),
    ).then((_) {
      if (mounted) {
        setState(() {
          _isGradeTourActive = false;
        });
      }
    });
  }

  void startClassesTour() {
    // Load DEMO MODE: Create a fake section with dummy data for practice
    setState(() {
      _sections = ['[TUTORIAL] Demo Section - Grade 10-A'];
      _ownedSections = ['[TUTORIAL] Demo Section - Grade 10-A'];
      _teacherType = 'Adviser';
      _teacherName = 'Demo Adviser';
      _isDemoMode = true;
      _isLoading = false;
    });

    // Navigate to the demo section after a short delay
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const SectionDetailPage(
            sectionName: "[TUTORIAL] Demo Section - Grade 10-A",
            startClassesTour: true,
          ),
        ),
      );
    });
  }

  void startTeachersTour() {
    // Load DEMO MODE: Create a fake section with dummy data for practice
    setState(() {
      _sections = ['[TUTORIAL] Demo Section - Grade 10-A'];
      _ownedSections = ['[TUTORIAL] Demo Section - Grade 10-A'];
      _teacherType = 'Adviser';
      _teacherName = 'Demo Adviser';
      _isDemoMode = true;
      _isLoading = false;
    });

    // Navigate to the demo section
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const SectionDetailPage(
            sectionName: "[TUTORIAL] Demo Section - Grade 10-A",
            startTeachersTour: true,
          ),
        ),
      );
    });
  }

  @override
  void dispose() {
    _teacherSubscription?.cancel();
    _sectionsSubscription?.cancel();
    super.dispose();
  }



  void resetTour() {
    setState(() {
      _isDemoMode = false;
      _isLoading = true;
    });
    _listenToData();
  }

  void _listenToData() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final firestore = FirebaseFirestore.instance;

    _teacherSubscription?.cancel();
    _teacherSubscription = firestore
        .collection('teachers')
        .doc(user.uid)
        .snapshots()
        .listen((doc) async {
      if (!doc.exists || !mounted || _isDemoMode) return;
      
      final data = doc.data();
      if (data == null) return;

      final sections = List<String>.from(data['sections'] ?? []).toSet().toList();
      List<String> ownedSections;
      
      if (data['ownedSections'] == null && (data['teacherType'] == 'Adviser')) {
        // Migration: treat all current sections as owned
        ownedSections = List<String>.from(sections);
        await firestore.collection('teachers').doc(user.uid).update({
          'ownedSections': ownedSections,
        });
        
        // Also ensure sections documents exist with adviserUid and required fields
        for (var sectionName in ownedSections) {
          await firestore.collection('sections').doc(sectionName).set({
            'adviserUid': user.uid,
            'studentUids': FieldValue.arrayUnion([]), // Ensure field exists
            'teacherUids': FieldValue.arrayUnion([]), // Ensure field exists
          }, SetOptions(merge: true));
        }
      } else {
        ownedSections = List<String>.from(data['ownedSections'] ?? []);
      }

      if (mounted) {
        setState(() {
          _teacherType = data['teacherType'] as String?;
          _teacherName = data['name'] as String? ?? 'Teacher';
          _sections = sections;
          _ownedSections = ownedSections;
          _isLoading = false;
        });
      }
    });

    // Optimized sections listener
    _sectionsSubscription?.cancel();
    if (widget.sectionsStream != null) {
      _sectionsSubscription = widget.sectionsStream!.listen((snapshots) {
        _processSections(snapshots, user.uid);
      });
    } else {
      _sectionsSubscription = firestore
          .collection('sections')
          .where('teacherUids', arrayContains: user.uid)
          .snapshots()
          .listen((snapshot) {
        _processSections(snapshot.docs, user.uid);
      });
    }
  }

  void _processSections(List<DocumentSnapshot> snapshots, String uid) {
    if (!mounted || _isDemoMode) return;
    
    final List<String> sectionsFromQuery = snapshots.map((doc) => doc.id).toList();
    final List<String> ownedFromQuery = snapshots
        .where((doc) => (doc.data() as Map<String, dynamic>?)?['adviserUid'] == uid)
        .map((doc) => doc.id)
        .toList();

    final Map<String, String?> newThumbnails = {};
    for (var doc in snapshots) {
      final data = doc.data() as Map<String, dynamic>?;
      if (data != null) {
        newThumbnails[doc.id] = data['sectionImageThumbnail'] as String?;
      }
    }

    setState(() {
      // Merge with existing lists but avoid duplicates
      _sections = ( { ..._sections, ...sectionsFromQuery } ).toList();
      _ownedSections = ( { ..._ownedSections, ...ownedFromQuery } ).toList();
      _sectionThumbnails = { ..._sectionThumbnails, ...newThumbnails };
      _isLoading = false;
    });
  }

  Future<void> _saveSections() async {
    if (_isDemoMode) return; // Prevent leaking demo data to Firestore
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await FirebaseFirestore.instance.collection('teachers').doc(user.uid).set(
        {
          'sections': _sections,
          'ownedSections': _ownedSections,
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('Error syncing sections to Firestore: $e');
    }
  }

  void _showAddSectionDialog(double screenWidth) {
    if (_ownedSections.isNotEmpty) {
      showDialog(
        context: context,
        builder: (context) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: screenWidth < 600 ? screenWidth * 0.9 : 400,
            ),
            child: Container(
              padding: const EdgeInsets.all(36),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                color: Colors.white,
                border: Border.all(color: Colors.amber.shade200, width: 2),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                   Container(
                     padding: const EdgeInsets.all(16),
                     decoration: BoxDecoration(
                       color: Colors.amber.shade50,
                       shape: BoxShape.circle,
                     ),
                     child: Icon(Icons.warning_amber_rounded, size: 48, color: Colors.amber.shade700),
                   ),
                   const SizedBox(height: 24),
                   Text(
                     'Limit Reached',
                     style: TextStyle(
                       fontSize: 22, 
                       fontWeight: FontWeight.bold,
                       color: Colors.amber.shade900,
                     ),
                   ),
                   const SizedBox(height: 16),
                   const Text(
                     'You can only create and manage one section at a time.',
                     textAlign: TextAlign.center,
                     style: TextStyle(fontSize: 16, height: 1.5),
                   ),
                   const SizedBox(height: 8),
                   Text(
                     'Please delete your existing section if you wish to create a new one.',
                     textAlign: TextAlign.center,
                     style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                   ),
                   const SizedBox(height: 24),
                   SizedBox(
                     width: double.infinity,
                     child: ElevatedButton(
                       onPressed: () => Navigator.pop(context),
                       style: ElevatedButton.styleFrom(
                         backgroundColor: Colors.amber.shade700,
                         foregroundColor: Colors.white,
                         padding: const EdgeInsets.symmetric(vertical: 12),
                         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                       ),
                       child: const Text('Understand', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                     ),
                   ),
                ],
              ),
            ),
          ),
        ),
      );
      return;
    }

    final TextEditingController controller = TextEditingController();
    String? selectedGrade;
    File? selectedImage;
    String? imageThumbnail;

    Future<void> pickImage(StateSetter dialogSetState) async {
      try {
        final ImagePicker picker = ImagePicker();
        final XFile? image = await picker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 70,
        );

        if (image == null) return;

        File? imageToUse;
        
        // Try to crop the image, but if it fails, use the original
        try {
          final CroppedFile? croppedFile = await ImageCropper().cropImage(
            sourcePath: image.path,
            aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
            uiSettings: [
              AndroidUiSettings(
                toolbarTitle: 'Crop Section Image',
                toolbarColor: HexColor("#116754"),
                toolbarWidgetColor: Colors.white,
                initAspectRatio: CropAspectRatioPreset.square,
                lockAspectRatio: true,
              ),
              IOSUiSettings(
                title: 'Crop Section Image',
                aspectRatioLockEnabled: true,
              ),
            ],
          );

          if (croppedFile != null) {
            imageToUse = File(croppedFile.path);
          } else {
            // User cancelled cropping, use original
            imageToUse = File(image.path);
          }
        } catch (cropError) {
          // Cropper failed, use the original image
          debugPrint('Cropping failed, using original image: $cropError');
          imageToUse = File(image.path);
        }


        // Try to compress the image to create a thumbnail
        String? thumbnailData;
        try {
          final Uint8List? compressed = await FlutterImageCompress.compressWithFile(
            imageToUse.path,
            minWidth: 100,
            minHeight: 100,
            quality: 50,
          );
          
          if (compressed != null) {
            thumbnailData = base64Encode(compressed);
          } else {
            // Compression returned null, read file directly
            final bytes = await imageToUse.readAsBytes();
            thumbnailData = base64Encode(bytes);
          }
        } catch (compressionError) {
          // Compression failed, read the file bytes directly
          debugPrint('Compression failed, using uncompressed image: $compressionError');
          try {
            final bytes = await imageToUse.readAsBytes();
            thumbnailData = base64Encode(bytes);
          } catch (readError) {
            debugPrint('Failed to read image bytes: $readError');
            // Will proceed with null thumbnail
          }
        }
        
        dialogSetState(() {
          selectedImage = imageToUse;
          imageThumbnail = thumbnailData;
        });
      } catch (e) {
        debugPrint('Error picking image: $e');
        // ignore: use_build_context_synchronously
        final messenger = ScaffoldMessenger.of(context);
        Future.microtask(() {
          messenger.showSnackBar(
            SnackBar(content: Text('Failed to pick image: $e')),
          );
        });
      }
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, dialogSetState) {
          return AlertDialog(
            title: const Text('Create New Section'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Set a name for your class section. This will be used by students to find and join your class.',
                    style: TextStyle(fontSize: 13, color: Colors.black54),
                  ),
                  const SizedBox(height: 24),
                  // Section Image Picker (Optional)
                  Center(
                    child: Column(
                      children: [
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              debugPrint('Section image picker tapped');
                              pickImage(dialogSetState);
                            },
                            borderRadius: BorderRadius.circular(50),
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: HexColor("#116754").withValues(alpha: 0.3),
                                  width: 2,
                                ),
                              ),
                              child: Stack(
                                children: [
                                  Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.black, width: 2.0),
                                    ),
                                    child: CircleAvatar(
                                      radius: 50,
                                      backgroundColor: HexColor("#116754").withValues(alpha: 0.1),
                                      backgroundImage: selectedImage != null
                                          ? FileImage(selectedImage!)
                                          : null,
                                      child: selectedImage == null
                                          ? Icon(
                                              Icons.class_,
                                              size: 50,
                                              color: HexColor("#116754"),
                                            )
                                          : null,
                                    ),
                                  ),
                                  Positioned(
                                    bottom: 0,
                                    right: 0,
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: HexColor("#116754"),
                                        shape: BoxShape.circle,
                                        border: Border.all(color: Colors.white, width: 2),
                                      ),
                                      child: const Icon(
                                        Icons.camera_alt,
                                        size: 16,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tap to add section image (optional)',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  LIMEDropdown<String>(
                    label: 'Grade Level',
                    value: selectedGrade,
                    items: const [
                      DropdownMenuItem(value: 'Grade 11', child: Text('Grade 11')),
                      DropdownMenuItem(value: 'Grade 12', child: Text('Grade 12')),
                    ],
                    onChanged: (value) => dialogSetState(() => selectedGrade = value),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Section Name',
                      hintText: 'e.g., AMBER',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Cancel', style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.bold)),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (selectedGrade == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please select a Grade Level')),
                    );
                    return;
                  }
                  
                  if (controller.text.trim().isNotEmpty) {
                    final rawName = controller.text.trim().toUpperCase();
                    final gradeNum = selectedGrade!.replaceAll('Grade ', '');
                    // Auto-format: "11 - AMBER"
                    final sectionName = "$gradeNum - $rawName"; 

                    final user = FirebaseAuth.instance.currentUser;
                    if (user == null) return;

                    // CHECK: Ensure section name is unique
                    final sectionDoc = await FirebaseFirestore.instance.collection('sections').doc(sectionName).get();
                    if (sectionDoc.exists) {
                       if (context.mounted) {
                          showDialog(
                            context: context,
                            builder: (context) => Dialog(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: screenWidth < 600 ? screenWidth * 0.9 : 400,
                  ),
                                child: Container(
                                  padding: const EdgeInsets.all(36),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(28),
                                    color: Colors.white,
                                    border: Border.all(color: Colors.amber.shade200, width: 2),
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                       Container(
                                         padding: const EdgeInsets.all(16),
                                         decoration: BoxDecoration(
                                           color: Colors.amber.shade50,
                                           shape: BoxShape.circle,
                                         ),
                                         child: Icon(Icons.error_outline_rounded, size: 48, color: Colors.amber.shade700),
                                       ),
                                       const SizedBox(height: 24),
                                       Text(
                                         'Name Taken',
                                         style: TextStyle(
                                           fontSize: 22, 
                                           fontWeight: FontWeight.bold,
                                           color: Colors.amber.shade900,
                                         ),
                                       ),
                                       const SizedBox(height: 16),
                                       Text(
                                         'The section name "$sectionName" has already been taken.',
                                         textAlign: TextAlign.center,
                                         style: const TextStyle(fontSize: 16, height: 1.5),
                                       ),
                                       const SizedBox(height: 8),
                                       Text(
                                         'Please choose a different name.',
                                         textAlign: TextAlign.center,
                                         style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                                       ),
                                       const SizedBox(height: 24),
                                       SizedBox(
                                         width: double.infinity,
                                         child: ElevatedButton(
                                           onPressed: () => Navigator.pop(context),
                                           style: ElevatedButton.styleFrom(
                                             backgroundColor: Colors.amber.shade700,
                                             foregroundColor: Colors.white,
                                             padding: const EdgeInsets.symmetric(vertical: 12),
                                             shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                           ),
                                           child: const Text('Try Again', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                         ),
                                       ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                       }
                       return; // Stop creation
                    }

                    // Add to local state (for instant feedback, though listener will catch it too)
                    setState(() {
                      if (!_sections.contains(sectionName)) _sections.add(sectionName);
                      if (!_ownedSections.contains(sectionName)) _ownedSections.add(sectionName);
                    });
                    await _saveSections();
                    
                    // Set adviserUid, adviserName, studentUids, and optional image in section document
                    final Map<String, dynamic> sectionData = {
                      'adviserUid': user.uid,
                      'adviserName': _teacherName,
                      'gradeLevel': selectedGrade,
                      'studentUids': [],
                      'teacherUids': [],
                    };

                    // Add image thumbnail if selected
                    if (imageThumbnail != null) {
                      sectionData['sectionImageThumbnail'] = imageThumbnail;
                    }

                    await FirebaseFirestore.instance.collection('sections').doc(sectionName).set(
                      sectionData,
                      SetOptions(merge: true),
                    );

                    if (context.mounted) {
                      Navigator.pop(context);
                      // Auto-navigate to the new section
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => SectionDetailPage(sectionName: sectionName),
                        ),
                      );
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: HexColor("#116754"),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Create Section', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        }
      ),
    );
  }

  void _deleteSection(int index) async {
    final sectionName = _sections[index];
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Section'),
        content: Text('Are you sure you want to delete "$sectionName"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: HexColor("#116754"), fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () async {
              final sectionToDelete = _sections[index];
              setState(() {
                _sections.removeAt(index);
                _ownedSections.remove(sectionToDelete);
              });
              await _saveSections();

              // 1. Fetch section data (schedule) before deleting
              try {
                final firestore = FirebaseFirestore.instance;
                final sectionDoc = await firestore.collection('sections').doc(sectionToDelete).get();
                
                List<dynamic> schedule = [];
                if (sectionDoc.exists) {
                  schedule = sectionDoc.data()?['schedule'] as List<dynamic>? ?? [];
                }

                final List<String> subjectsInRoom = schedule
                    .whereType<Map<String, dynamic>>()
                    .map((item) => (item['subject'] as String?) ?? '')
                    .where((s) => s.isNotEmpty)
                    .toList();

                // 2. Find all students enrolled in this section
                final studentsWithSection = await firestore
                    .collection('students')
                    .where('sections', arrayContains: sectionToDelete)
                    .get();

                final batch = firestore.batch();

                // 3. Purge grades and remove section from all enrolled students
                for (var doc in studentsWithSection.docs) {
                  final updates = <String, dynamic>{};
                  
                  // Delete grades for subjects in this section
                  for (var subject in subjectsInRoom) {
                    updates['grades.$subject'] = FieldValue.delete();
                  }
                  
                  // Remove section from student's sections list
                  updates['sections'] = FieldValue.arrayRemove([sectionToDelete]);
                  
                  batch.update(doc.reference, updates);
                }

                // 4. Remove from all teachers' sections
                final teachersWithSection = await firestore
                    .collection('teachers')
                    .where('sections', arrayContains: sectionToDelete)
                    .get();
                for (var doc in teachersWithSection.docs) {
                  batch.update(doc.reference, {
                    'sections': FieldValue.arrayRemove([sectionToDelete]),
                    'ownedSections': FieldValue.arrayRemove([sectionToDelete]),
                  });
                }

                // 5. Delete the section document
                batch.delete(firestore.collection('sections').doc(sectionToDelete));

                await batch.commit();
                debugPrint('Permanently deleted $sectionToDelete and purged associated data for ${studentsWithSection.docs.length} students');
              } catch (e) {
                debugPrint('Error during robust section deletion: $e');
              }

              if (context.mounted) {
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final isAdviser = _teacherType == 'Adviser';

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isMobile = width <= 600;
        final isDesktop = width > 900;
        
        final horizontalPadding = isMobile ? 16.0 : 24.0;
        final titleSize = isMobile ? 28.0 : 32.0;

        return Container(
          color: Colors.grey[50],
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.all(horizontalPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!isMobile) ...[
                              Text(
                                'My Classes',
                                style: TextStyle(
                                  fontSize: titleSize,
                                  fontWeight: FontWeight.bold,
                                  color: HexColor("#116754"),
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],
                            Text(
                              isAdviser 
                                  ? 'Manage your sections' 
                                  : 'Manage your classes and students',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isAdviser)
                        Padding(
                          padding: const EdgeInsets.only(left: 8.0),
                          child: ElevatedButton.icon(
                            key: _createButtonKey,
                            onPressed: () => _showAddSectionDialog(width),
                            icon: const Icon(Icons.add, size: 20),
                            label: Text(isMobile ? 'Create' : 'Create Section'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: HexColor("#116754"),
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(
                                horizontal: isMobile ? 12 : 20, 
                                vertical: isMobile ? 8 : 12
                              ),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
    
                  if (_sections.isEmpty)
                    _buildEmptyState(isAdviser)
                  else ...[
                    if (_ownedSections.isNotEmpty) ...[
                      Text(
                        'My Sections (Adviser)',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: HexColor("#116754"),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildSectionGrid(_ownedSections, isOwned: true, isDesktop: isDesktop),
                      const SizedBox(height: 24),
                    ],
                    if (_sections.where((s) => !_ownedSections.contains(s)).isNotEmpty) ...[
                      Text(
                        'Assigned Classes (Subject Teacher)',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: HexColor("#116754"),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildSectionGrid(
                        _sections.where((s) => !_ownedSections.contains(s)).toList(),
                        isOwned: false,
                        isDesktop: isDesktop
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSectionGrid(List<String> sections, {required bool isOwned, required bool isDesktop}) {
    if (isDesktop) {
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          mainAxisExtent: 120, // Fixed height for cards
        ),
        itemCount: sections.length,
        itemBuilder: (context, index) => _buildSectionCard(
          sections[index], 
          isOwned: isOwned,
          key: index == 0 ? _firstSectionKey : null,
        ),
      );
    }
    return Column(
      children: sections.asMap().entries.map((entry) {
        return _buildSectionCard(
          entry.value, 
          isOwned: isOwned,
          key: entry.key == 0 ? _firstSectionKey : null,
        );
      }).toList(),
    );
  }

  Widget _buildEmptyState(bool isAdviser) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          children: [
            Icon(Icons.class_, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              isAdviser ? 'No sections created yet' : 'No classes available',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
            if (isAdviser) ...[
              const SizedBox(height: 8),
              Text(
                'Click "Create" to get started',
                style: TextStyle(fontSize: 14, color: Colors.grey[500]),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard(String section, {required bool isOwned, Key? key}) {
    return Padding(
      key: key,
      padding: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => SectionDetailPage(
                sectionName: section,
                startGradeTour: _isGradeTourActive,
                // If we are in global demo mode, we might want to propagate other flags here if needed
              ),
            ),
          ).then((_) {
            if (mounted) {
              setState(() {
                _isGradeTourActive = false;
              });
            }
          });
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey[300]!),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Builder(
                builder: (context) {
                  final String? thumbnail = _sectionThumbnails[section];
                  final Uint8List? thumbBytes = thumbnail != null ? base64Decode(thumbnail) : null;
                  
                  return Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: (isOwned ? HexColor("#116754") : Colors.green).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black, width: 1.5),
                      ),
                      child: CircleAvatar(
                        radius: 28,
                        backgroundColor: Colors.transparent,
                        backgroundImage: thumbBytes != null ? MemoryImage(thumbBytes) : null,
                        child: thumbBytes == null
                            ? Icon(
                                isOwned ? Icons.class_ : Icons.school,
                                color: isOwned ? HexColor("#116754") : Colors.green[700],
                                size: 32,
                              )
                            : null,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  section,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (isOwned)
                IconButton(
                  icon: Icon(Icons.delete, color: Colors.red[400]),
                  onPressed: () {
                    final idx = _sections.indexOf(section);
                    if (idx != -1) _deleteSection(idx);
                  },
                ),
              Icon(
                Icons.arrow_forward_ios,
                color: HexColor("#116754"),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

