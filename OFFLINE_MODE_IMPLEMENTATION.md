# Offline/Online Mode Implementation

This document explains how the offline/online mode has been implemented in the LIME application, similar to messenger apps like WhatsApp or Facebook Messenger.

## Overview

The app now supports:
- **Offline access** when logged in with an account
- **Automatic data synchronization** when connectivity is restored
- **Visual indicators** showing online/offline status
- **Seamless data persistence** using Firestore's built-in offline capabilities

## Key Components

### 1. Connectivity Service (`lib/services/connectivity_service.dart`)
- Monitors network connectivity status (WiFi, mobile data, ethernet)
- Provides a stream that emits connectivity changes in real-time
- Singleton service accessible throughout the app

**Usage:**
```dart
final connectivityService = ConnectivityService();
bool isOnline = connectivityService.isOnline;
Stream<bool> connectivityStream = connectivityService.connectivityStream;
```

### 2. Offline Sync Service (`lib/services/offline_sync_service.dart`)
- Automatically syncs data when connectivity is restored
- Manages synchronization state and timing
- Works with Firestore's offline persistence

**Features:**
- Listens for connectivity changes
- Triggers sync when coming back online
- Prevents duplicate sync operations
- Tracks last sync time

### 3. Connectivity Indicator Widget (`lib/widgets/connectivity_indicator.dart`)
- Visual indicator showing online/offline status
- Two variants:
  - `ConnectivityIndicator`: Small badge with optional text
  - `OfflineBanner`: Full-width banner at top of screen

**Usage:**
```dart
// Small indicator in AppBar
ConnectivityIndicator(showText: false)

// Full banner
OfflineBanner()
```

### 4. Firestore Offline Persistence
- Enabled automatically on mobile platforms (Android/iOS)
- Enabled explicitly on web/desktop platforms
- Caches data locally for offline access
- Automatically syncs pending writes when online

## How It Works

### When Online:
1. App fetches data from Firestore in real-time
2. All writes are immediately synced to the server
3. Data is cached locally for offline access
4. Green indicator shows "Online" status

### When Offline:
1. App continues to work using cached data
2. All reads come from local cache
3. Writes are queued locally
4. Orange indicator shows "Offline" status
5. Banner appears at top: "You're offline. Some features may be limited."

### When Coming Back Online:
1. Connectivity service detects network restoration
2. Sync service automatically triggers synchronization
3. All pending writes are sent to the server
4. Local cache is updated with latest server data
5. Indicator changes back to "Online"

## User Experience

### Visual Feedback:
- **AppBar Indicator**: Small dot in the top-right corner of mobile AppBars
  - Green dot = Online
  - Orange dot = Offline
- **Banner**: Full-width banner at top of screen when offline
  - Shows message: "You're offline. Some features may be limited."

### Functionality:
- **Read Operations**: Always work (from cache when offline)
- **Write Operations**: 
  - Work immediately when online
  - Queued and synced automatically when offline
- **Real-time Updates**: 
  - Continue when online
  - Resume when connectivity is restored

## Technical Details

### Firestore Offline Persistence
Firestore automatically:
- Caches documents locally
- Queues writes when offline
- Syncs when connectivity is restored
- Handles conflicts automatically

### Connectivity Detection
Uses `connectivity_plus` package to detect:
- WiFi connections
- Mobile data (cellular)
- Ethernet connections
- No connectivity

### Data Synchronization
- Automatic sync when coming online
- 2-second delay to ensure network stability
- Prevents duplicate sync operations
- Error handling for failed syncs

## Configuration

### Initialization
Services are initialized in `main.dart`:
```dart
// Initialize connectivity service
await ConnectivityService().init();

// Initialize sync service
await OfflineSyncService().init();

// Enable Firestore persistence
await FirebaseFirestore.instance.enablePersistence();
```

### Platform Support
- **Mobile (Android/iOS)**: Full offline support with persistence
- **Web/Desktop**: Offline support enabled where supported
- **All Platforms**: Connectivity detection works everywhere

## Best Practices

1. **Always check connectivity** before critical operations
2. **Use Firestore snapshots** - they work offline automatically
3. **Handle offline gracefully** - show appropriate messages
4. **Test offline scenarios** - disable network during testing
5. **Monitor sync status** - use `OfflineSyncService.isSyncing`

## Testing Offline Mode

1. **Enable Airplane Mode** on your device
2. **Disable WiFi** in your development environment
3. **Use Network Throttling** in browser DevTools
4. **Monitor Logs** for sync messages

## Future Enhancements

Potential improvements:
- Background sync using WorkManager
- Manual sync button for users
- Sync progress indicator
- Conflict resolution UI
- Offline queue management UI

## Troubleshooting

### Issue: Data not syncing when online
- Check connectivity service is initialized
- Verify Firestore persistence is enabled
- Check logs for sync errors

### Issue: Offline data not available
- Ensure user is logged in
- Check Firestore cache is enabled
- Verify data was previously loaded

### Issue: Indicator not updating
- Check connectivity service stream is active
- Verify widget is listening to stream
- Check for errors in console

## Notes

- Offline mode requires user to be logged in
- Some features may be limited when offline (e.g., image uploads)
- Data sync happens automatically - no user action required
- Works seamlessly with existing Firestore queries and snapshots
