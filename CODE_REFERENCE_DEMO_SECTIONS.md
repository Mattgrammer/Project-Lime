# Demo Sections Implementation - Code Reference

## Overview of All Changes

### 1. DemoSectionService (NEW)
**Location:** `lib/services/demo_section_service.dart`

```dart
import 'package:shared_preferences/shared_preferences.dart';

class DemoSectionService {
  static const String _flagKey = 'show_demo_sections';

  /// Enable demo sections (for tutorial mode)
  static Future<void> enableDemoSections() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_flagKey, true);
  }

  /// Disable demo sections (for normal app usage)
  static Future<void> disableDemoSections() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_flagKey, false);
  }

  /// Check if demo sections are currently enabled
  static Future<bool> areDemoSectionsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_flagKey) ?? false;
  }

  /// Toggle demo sections visibility
  static Future<bool> toggleDemoSections() async {
    final prefs = await SharedPreferences.getInstance();
    final currentState = prefs.getBool(_flagKey) ?? false;
    await prefs.setBool(_flagKey, !currentState);
    return !currentState;
  }
}
```

**Usage:**
```dart
// Enable demos for tutorial
await DemoSectionService.enableDemoSections();

// Disable demos after tutorial
await DemoSectionService.disableDemoSections();

// Check if enabled
final enabled = await DemoSectionService.areDemoSectionsEnabled();
```

---

### 2. RequestSectionPage Updates
**Location:** `lib/pages/student/request_section_page.dart`

**Add to imports:**
```dart
import 'package:shared_preferences/shared_preferences.dart';
```

**Add to state class:**
```dart
class _RequestSectionPageState extends State<RequestSectionPage> {
  // ... existing fields ...
  bool _showDemoSections = false;  // NEW
  
  @override
  void initState() {
    super.initState();
    _loadDemoSectionsFlag();  // NEW - Load before _loadData
    _loadData();
    // ... rest of init ...
  }
}
```

**Add new method:**
```dart
Future<void> _loadDemoSectionsFlag() async {
  final prefs = await SharedPreferences.getInstance();
  if (mounted) {
    setState(() {
      _showDemoSections = prefs.getBool('show_demo_sections') ?? false;
    });
  }
}
```

**Update _loadData() method:**
```dart
Future<void> _loadData() async {
  try {
    final firestore = FirebaseFirestore.instance;
    final sectionsSnapshot = await firestore.collection('sections').get();

    final Set<String> sections = {};
    _sectionOwners.clear();
    _sectionThumbnails.clear();
    _sectionImageUrls.clear();

    for (var doc in sectionsSnapshot.docs) {
      final sectionName = doc.id;
      
      // NEW: Skip demo sections unless explicitly showing them
      if (sectionName.contains('[TUTORIAL]') || sectionName.contains('Demo Section')) {
        if (!_showDemoSections) {
          continue;
        }
      }

      final data = doc.data();
      sections.add(sectionName);
      // ... rest of processing ...
    }

    if (mounted) {
      setState(() {
        _allSections = sections.toList()..sort();
        _filteredSections = List.from(_allSections);
        _isLoading = false;
      });
    }
  } catch (e) {
    debugPrint('Error loading sections: $e');
    if (mounted) setState(() => _isLoading = false);
  }
}
```

---

### 3. SchedulePage Updates
**Location:** `lib/pages/student/schedule_page.dart`

**Add to imports:**
```dart
import 'package:shared_preferences/shared_preferences.dart';
```

**Add to state class:**
```dart
class _SchedulePageState extends State<SchedulePage> {
  bool _isLoading = true;
  bool _showDemoSections = false;  // NEW
  List<Map<String, dynamic>> _scheduleItems = [];
  StreamSubscription? _sectionsSub;

  @override
  void initState() {
    super.initState();
    _loadDemoSectionsFlag();  // NEW - Load before _initListener
    _initListener();
  }
}
```

**Add new method:**
```dart
Future<void> _loadDemoSectionsFlag() async {
  final prefs = await SharedPreferences.getInstance();
  if (mounted) {
    setState(() {
      _showDemoSections = prefs.getBool('show_demo_sections') ?? false;
    });
  }
}
```

**Update _processSchedule() method:**
```dart
void _processSchedule(QuerySnapshot snapshot) {
  if (!mounted) return;
  List<Map<String, dynamic>> allItems = [];

  for (var doc in snapshot.docs) {
    final sectionName = doc.id;
    
    // NEW: Skip demo sections unless explicitly showing them
    if ((sectionName.contains('[TUTORIAL]') || sectionName.contains('Demo Section')) 
        && !_showDemoSections) {
      continue;
    }
    
    final data = doc.data() as Map<String, dynamic>?;
    if (data?['schedule'] is List) {
      final List<dynamic> schedList = data!['schedule'];
      for (final item in schedList) {
        if (item is Map<String, dynamic>) {
          allItems.add({
            ...item,
            'section': doc.id,
          });
        }
      }
    }
  }

  if (mounted) {
    setState(() {
      _scheduleItems = allItems;
      _isLoading = false;
    });
  }
}
```

---

### 4. HomePage Updates
**Location:** `lib/pages/student/home_page.dart`

**Update _processSectionData() method:**
```dart
void _processSectionData(QuerySnapshot snapshot) {
  if (!mounted) return;
  int todayClassesCount = 0;
  List<Map<String, dynamic>> todayDetails = [];
  final currentDay = _getDayName();

  for (var doc in snapshot.docs) {
    final sectionName = doc.id;
    
    // NEW: Skip demo sections
    if ((sectionName.contains('[TUTORIAL]') || sectionName.contains('Demo Section'))) {
      continue;
    }
    
    final data = doc.data() as Map<String, dynamic>?;
    final schedule = data?['schedule'] as List?;
    if (schedule != null) {
      for (var item in schedule) {
        if (item is Map<String, dynamic> && item['day'] == currentDay) {
          todayClassesCount++;
          todayDetails.add({
            ...item,
            'sectionTitle': doc.id,
          });
        }
      }
    }
  }

  if (mounted) {
    final Set<String> s1Subjects = {};
    final Set<String> s2Subjects = {};
    for (var doc in snapshot.docs) {
      final sectionName = doc.id;
      
      // NEW: Skip demo sections
      if ((sectionName.contains('[TUTORIAL]') || sectionName.contains('Demo Section'))) {
        continue;
      }
      
      final data = doc.data() as Map<String, dynamic>?;
      final schedule = data?['schedule'] as List?;
      if (schedule != null) {
        for (var item in schedule) {
          if (item is Map<String, dynamic> && item['subject'] != null) {
            final sem = item['semester'] as int? ?? 1;
            if (sem == 1) {
              s1Subjects.add(item['subject']);
            } else {
              s2Subjects.add(item['subject']);
            }
          }
        }
      }
    }

    setState(() {
      _upcomingClasses = todayClassesCount;
      _todayClassesDetails = todayDetails;
      _enrolledS1 = s1Subjects.length;
      _enrolledS2 = s2Subjects.length;
      _lastSectionsSnapshot = snapshot;
      _calculateSemesterGPAs();
      _isLoading = false;
    });
  }
}
```

---

### 5. GuidePointer Updates
**Location:** `lib/widgets/guide_pointer.dart`

**Add to imports:**
```dart
import '../services/demo_section_service.dart';
```

**Update show() method:**
```dart
static void show(BuildContext context, {
  required List<GuideStep> steps,
  required VoidCallback onComplete,
  int? totalStepsOverride,
  int initialStepOffset = 0,
}) {
  debugPrint('GUIDE: show() called with ${steps.length} steps');

  // NEW: Enable demo sections when guide starts
  DemoSectionService.enableDemoSections().then((_) {
    debugPrint('GUIDE: Demo sections enabled');
  });

  dismiss();
  
  final overlay = Overlay.of(context, rootOverlay: true);
  
  _currentOverlay = OverlayEntry(
    builder: (context) => GuidePointer(
      key: _globalKey,
      steps: steps,
      onComplete: () {
        debugPrint('GUIDE: onComplete triggered');
        dismiss();
        onComplete();
      },
      totalStepsOverride: totalStepsOverride,
      initialStepOffset: initialStepOffset,
    ),
  );
  overlay.insert(_currentOverlay!);
  debugPrint('GUIDE: Overlay inserted into rootOverlay successfully');
}
```

**Update dismiss() method:**
```dart
static void dismiss() {
  if (_currentOverlay != null) {
    debugPrint('GUIDE: dismissing current overlay');
    _currentOverlay?.remove();
    _currentOverlay = null;

    // NEW: Disable demo sections when guide ends
    DemoSectionService.disableDemoSections().then((_) {
      debugPrint('GUIDE: Demo sections disabled');
    });
  }
}
```

---

## Integration Pattern

### Adding Demo Filtering to New Pages

When creating a new page that queries sections, use this pattern:

```dart
class _MyPageState extends State<MyPage> {
  bool _showDemoSections = false;

  @override
  void initState() {
    super.initState();
    _loadDemoSectionsFlag();
    _loadSections();
  }

  Future<void> _loadDemoSectionsFlag() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _showDemoSections = prefs.getBool('show_demo_sections') ?? false;
      });
    }
  }

  void _processSections(QuerySnapshot snapshot) {
    final sections = [];
    
    for (var doc in snapshot.docs) {
      final sectionName = doc.id;
      
      // Filter demo sections
      if ((sectionName.contains('[TUTORIAL]') || sectionName.contains('Demo Section'))
          && !_showDemoSections) {
        continue;
      }
      
      // Process section...
    }
  }
}
```

---

## Debugging

### Check Flag Status
```dart
// In any page/widget
final enabled = await DemoSectionService.areDemoSectionsEnabled();
debugPrint('Demo sections enabled: $enabled');
```

### Force Enable (Testing)
```dart
// Temporarily enable to test
await DemoSectionService.enableDemoSections();
// Pages should reload and show demo sections
```

### Clear Preference (Reset)
```dart
// Reset flag to false (default)
final prefs = await SharedPreferences.getInstance();
await prefs.remove('show_demo_sections');
// Pages should reload without demo sections
```

---

## Summary

All changes implement a clean separation:
- **Normal Use:** Demo sections hidden (show_demo_sections = false)
- **Tutorial Mode:** Demo sections visible (show_demo_sections = true)
- **Persistent:** Flag saved to device, survives app restart
- **Consistent:** Same filtering across all pages
