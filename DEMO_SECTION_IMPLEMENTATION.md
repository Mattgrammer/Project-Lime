# Demo Section Visibility Implementation - Complete

## Overview
Successfully implemented persistent demo section visibility using SharedPreferences. Demo sections are now hidden by default and only appear when the tutorial/guide is active.

## Changes Made

### 1. **New Service: DemoSectionService** 
📄 `lib/services/demo_section_service.dart`

Provides utility methods to manage demo section visibility:
- `enableDemoSections()` - Show demo sections (called when tutorial starts)
- `disableDemoSections()` - Hide demo sections (called when tutorial ends)
- `areDemoSectionsEnabled()` - Check current state
- `toggleDemoSections()` - Toggle visibility

Uses SharedPreferences key: `show_demo_sections`

### 2. **Updated Request Section Page**
📄 `lib/pages/student/request_section_page.dart`

**Changes:**
- ✅ Added `SharedPreferences` import
- ✅ Added `bool _showDemoSections = false` state variable
- ✅ Added `_loadDemoSectionsFlag()` method to load from SharedPreferences on init
- ✅ Updated `_loadData()` to filter demo sections:
  - Detects sections containing `[TUTORIAL]` or `Demo Section` in the name
  - Only includes them if `_showDemoSections == true`
  - Default: Hidden from normal app usage

### 3. **Updated Schedule Page**
📄 `lib/pages/student/schedule_page.dart`

**Changes:**
- ✅ Added `SharedPreferences` import
- ✅ Added `bool _showDemoSections = false` state variable
- ✅ Added `_loadDemoSectionsFlag()` method
- ✅ Updated `_processSchedule()` to filter demo sections
  - Same filtering logic as request page
  - Prevents demo schedules from showing in normal view

### 4. **Updated Guide Pointer Widget**
📄 `lib/widgets/guide_pointer.dart`

**Changes:**
- ✅ Added `DemoSectionService` import
- ✅ Modified `show()` static method:
  - Now calls `DemoSectionService.enableDemoSections()` when tutorial starts
  - Demo sections become visible during guide
- ✅ Modified `dismiss()` static method:
  - Calls `DemoSectionService.disableDemoSections()` when tutorial ends
  - Demo sections hide after guide completes

## How It Works

### Normal App Usage (No Tutorial)
```
User opens app → _showDemoSections = false (default)
                → Request Section page loads
                → Demo sections FILTERED OUT
                → User sees only real sections
```

### When Tutorial Starts
```
User clicks "Help" / Tutorial button
→ GuidePointer.show() called
→ DemoSectionService.enableDemoSections() sets flag = true
→ Pages reload with demo sections visible
→ Tutorial highlights demo section for learning
```

### When Tutorial Ends
```
Tutorial completes
→ GuidePointer.dismiss() called
→ DemoSectionService.disableDemoSections() sets flag = false
→ Pages reload without demo sections
→ Demo data hidden from normal usage again
```

## Demo Section Detection

The implementation detects demo sections by name pattern:
- `[TUTORIAL] Demo Section - Grade 10-A`
- `Demo Section - Grade 10-A`
- Any section containing `[TUTORIAL]` or `Demo Section`

## Testing Checklist

- [ ] Open app normally → "Demo Section - Grade 10-A" should NOT appear in Request Section
- [ ] Click Help/Tutorial button → Demo section should APPEAR
- [ ] Complete tutorial → Demo section should DISAPPEAR again
- [ ] Force close app and reopen → Demo section should still be hidden
- [ ] Test Schedule page → Same behavior as Request Section page
- [ ] Test with multiple demo sections → All should be filtered consistently

## Technical Details

**SharedPreferences Key:** `show_demo_sections`
- Type: Boolean
- Default: `false` (hidden)
- Scope: Per user device (saved locally)
- Persistence: Survives app restarts until explicitly changed

**Filtering Logic:**
```dart
if ((sectionName.contains('[TUTORIAL]') || sectionName.contains('Demo Section')) 
    && !_showDemoSections) {
  continue; // Skip this section
}
```

## Notes

- ✅ No breaking changes to existing functionality
- ✅ Backward compatible with non-demo sections
- ✅ Uses existing SharedPreferences dependency
- ✅ Integrates cleanly with GuidePointer system
- ✅ Applies to both RequestSectionPage and SchedulePage
- ✅ Prevents students from seeing demo data in normal app usage
