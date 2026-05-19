# Demo Section Visibility - Implementation Summary

## ✅ What Was Implemented

A complete system to **hide demo sections from students during normal app usage** and **show them only during tutorial/onboarding mode**.

### The Problem
The "Demo Section - Grade 10-A" was visible to students in the Request Section page even when they weren't in tutorial mode. This was confusing and not part of the normal user experience.

### The Solution
A persistent flag stored in SharedPreferences (`show_demo_sections`) that controls demo visibility:
- **Default State:** Hidden (flag = false)
- **Tutorial Active:** Shown (flag = true)
- **Tutorial Ends:** Hidden again (flag = false)

---

## 📋 Files Modified/Created

### NEW FILE: `lib/services/demo_section_service.dart`
Service class to manage demo section visibility across the app.

**Key Methods:**
```dart
DemoSectionService.enableDemoSections()  // Show demo sections
DemoSectionService.disableDemoSections() // Hide demo sections
```

### MODIFIED: `lib/pages/student/request_section_page.dart`
- Added SharedPreferences import
- Added `_showDemoSections` state variable
- Added `_loadDemoSectionsFlag()` method
- Updated `_loadData()` to filter demo sections

**Filtering Logic:**
```dart
if ((sectionName.contains('[TUTORIAL]') || sectionName.contains('Demo Section')) 
    && !_showDemoSections) {
  continue; // Skip demo sections
}
```

### MODIFIED: `lib/pages/student/schedule_page.dart`
- Added SharedPreferences import
- Added `_showDemoSections` state variable
- Added `_loadDemoSectionsFlag()` method
- Updated `_processSchedule()` to filter demo sections

### MODIFIED: `lib/pages/student/home_page.dart`
- Updated `_processSectionData()` to filter demo sections
- Prevents demo data from appearing in dashboard stats/schedules

### MODIFIED: `lib/widgets/guide_pointer.dart`
- Added DemoSectionService import
- Updated `show()` to enable demo sections when tutorial starts
- Updated `dismiss()` to disable demo sections when tutorial ends

---

## 🔄 How It Works

### User Flow - Normal App Usage
```
1. Student opens app
2. SharedPreferences loads: show_demo_sections = false
3. RequestSectionPage loads sections
4. Demo sections are FILTERED OUT
5. Student only sees real sections
```

### User Flow - With Tutorial
```
1. Student clicks "Help" or "Tutorial" button
2. GuidePointer.show() is called
3. DemoSectionService.enableDemoSections() → sets flag = true
4. Pages reload with demo sections visible
5. Tutorial highlights demo section
6. Student learns how to use the feature
7. Tutorial ends
8. GuidePointer.dismiss() is called
9. DemoSectionService.disableDemoSections() → sets flag = false
10. Demo sections disappear
```

---

## 🎯 Demo Section Detection

Any section with the following in its name is treated as a demo section:
- Contains `[TUTORIAL]` (e.g., `[TUTORIAL] Demo Section`)
- Contains `Demo Section` (e.g., `Demo Section - Grade 10-A`)

**In Firestore, name your demo sections like:**
- ✅ `Demo Section - Grade 10-A`
- ✅ `[TUTORIAL] Grade 10-A`
- ✅ `[TUTORIAL] Demo Section`

---

## 🧪 Testing Steps

### Test 1: Normal App Usage (No Tutorial)
```
1. Open app on a fresh device/account
2. Go to Request Section page
3. EXPECT: "Demo Section" does NOT appear ✓
4. Go to Schedule page
5. EXPECT: Demo sections do NOT appear ✓
6. Check home page stats
7. EXPECT: Demo data does NOT affect counts ✓
```

### Test 2: Enable Tutorial
```
1. In your app, trigger the tutorial (find the Help button)
2. GuidePointer.show() will be called
3. EXPECT: Demo sections NOW APPEAR in Request Section page ✓
4. Follow the tutorial steps
5. EXPECT: Demo section is highlighted/visible ✓
```

### Test 3: Complete Tutorial
```
1. Complete or close the tutorial
2. GuidePointer.dismiss() will be called
3. EXPECT: Demo sections DISAPPEAR ✓
4. Force close the app
5. Reopen the app
6. EXPECT: Demo sections are still hidden ✓
```

### Test 4: Multiple Demo Sections
```
1. In Firestore, create multiple demo sections:
   - "Demo Section - Math"
   - "[TUTORIAL] Science Lab"
2. Open app normally
3. EXPECT: NEITHER appears ✓
4. Start tutorial
5. EXPECT: BOTH appear ✓
6. End tutorial
7. EXPECT: BOTH disappear ✓
```

---

## 🔧 Technical Details

### SharedPreferences Key
- **Key Name:** `show_demo_sections`
- **Type:** Boolean
- **Default:** `false` (demo sections hidden)
- **Persistence:** Saved to device storage, survives app restarts
- **Scope:** Per-user (unless SharedPreferences is cleared)

### Filtering Applied To
1. **RequestSectionPage** → Hides demo sections from "Join a Section" flow
2. **SchedulePage** → Hides demo schedules from calendar
3. **HomePage** → Prevents demo data from affecting dashboard stats/counts

### Integration with GuidePointer
- `GuidePointer.show()` → `enableDemoSections()`
- `GuidePointer.dismiss()` → `disableDemoSections()`

---

## 📝 Notes for Developers

### Adding More Pages with Demo Filtering
If you add new pages that query sections, include this pattern:

```dart
// At the top of initState or similar
Future<void> _loadDemoSectionsFlag() async {
  final prefs = await SharedPreferences.getInstance();
  if (mounted) {
    setState(() {
      _showDemoSections = prefs.getBool('show_demo_sections') ?? false;
    });
  }
}

// When processing sections
for (var doc in snapshot.docs) {
  final sectionName = doc.id;
  
  // Skip demo sections unless showing them
  if ((sectionName.contains('[TUTORIAL]') || sectionName.contains('Demo Section')) 
      && !_showDemoSections) {
    continue;
  }
  
  // ... process section
}
```

### Future Enhancements
- Add a "Show Demo Sections" toggle in settings for advanced users
- Log when demo sections are shown/hidden for analytics
- Add different demo sections for different features
- Create a "First Time User" flow that automatically shows tutorial on first login

---

## ✨ Benefits

✅ **Clean User Experience** - Students don't see confusing demo data in normal usage
✅ **Educational Tool** - Demo sections are available when students need help
✅ **Persistent** - Flag saved to device, so setting persists across sessions
✅ **Consistent** - Same filtering applied across all student-facing pages
✅ **Easy to Manage** - Simple naming convention for demo sections in Firestore
✅ **No Breaking Changes** - Existing functionality unaffected
