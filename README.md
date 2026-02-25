# offline_sync_kit

**Offline-first background sync for Flutter.**

Queue any local Dart model while offline, then automatically sync it to any REST API when connectivity returns — with WorkManager background execution, local notifications, battery/lifecycle awareness, and a generic model abstraction that requires **zero code generation**.

---

## Features

| Feature | Details |
|---|---|
| 📦 Generic queue | Queue any model via a `toJson` lambda — no Hive annotations in your own code |
| 🔄 Background sync | WorkManager periodic task syncs every N hours while the app is closed |
| 🛑 Foreground guard | Sync pauses automatically when the user opens the app |
| 🔋 Battery aware | Skips sync below a configurable battery percentage |
| 🌐 Connectivity + VPN | Optional VPN callback; skips sync with no internet |
| 🔁 Auto-retry | Configurable max retries; permanently failed records are marked `dead` |
| 🔔 Notifications | Summary notification after each sync cycle |
| 🎣 Hooks | `onSuccess`, `onFailure`, `onSyncStart`, `onSyncComplete` per entity |
| 🏗️ No code-gen | Records stored as plain maps; no `build_runner` needed |

---

## Installation

```yaml
# pubspec.yaml
dependencies:
  offline_sync_kit: ^0.1.0
```

### Android — `AndroidManifest.xml`

Add inside the `<manifest>` element (outside `<application>`):

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
```

Inside `<application>`:

```xml
<service
    android:name="androidx.work.impl.background.systemjob.SystemJobService"
    android:permission="android.permission.BIND_JOB_SERVICE"
    android:exported="true"/>
```

---

## Quick start

### Step 1 — Declare the WorkManager dispatcher at the **top level** of `main.dart`

> ⚠️ This **must** be a top-level function. WorkManager runs it in a separate
> Dart isolate that has no access to the main isolate's memory.  
> Re-supply your `SyncConfig` inside `configFactory`.

```dart
// main.dart — top-level, NOT inside a class
@pragma('vm:entry-point')
void myBackgroundDispatcher() {
  BackgroundSyncDispatcher.callbackDispatcher(
    configFactory: () => SyncConfig(
      baseUrl: 'https://api.example.com',
      // Read token from SharedPreferences / secure storage inside the isolate
      getAuthToken: () async => 'Bearer ${await MyAuth.getSavedToken()}',
      entities: buildSyncEntities(),
    ),
  );
}
```

### Step 2 — Initialise in `main()`

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Tracks foreground/background — must be called before runApp
  AppLifecycleObserver.initialize();

  await OfflineSyncKit.initialize(
    backgroundDispatcher: myBackgroundDispatcher,
    config: SyncConfig(
      baseUrl: 'https://api.example.com',
      getAuthToken: () async => 'Bearer ${await MyAuth.getToken()}',
      entities: buildSyncEntities(),
      showSyncNotifications: true,
      onSyncComplete: (ok, fail) => print('Sync done ✅$ok ❌$fail'),
    ),
  );

  runApp(const MyApp());
}
```

### Step 3 — Define entity configs

```dart
List<SyncEntityConfig> buildSyncEntities() => [
  // Create
  SyncEntityConfig<Order>(
    boxKey: 'create_orders',          // unique Hive box name — never rename
    endpoint: '/orders',
    method: HttpMethod.post,
    toJson: (o) => o.toJson(),
    extractServerId: (data) => data['id']?.toString(),
    onSuccess: (r) => print('Created on server: ${r.serverId}'),
    maxRetries: 3,
  ),

  // Update — URL suffix contains the server id
  SyncEntityConfig<Map<String, dynamic>>(
    boxKey: 'update_orders',
    endpoint: '/orders',
    method: HttpMethod.patch,
    buildPathSuffix: (record) => '/${record.serverId}',
    toJson: (m) => m,
  ),

  // Delete
  SyncEntityConfig<Map<String, dynamic>>(
    boxKey: 'delete_orders',
    endpoint: '/orders',
    method: HttpMethod.delete,
    buildPathSuffix: (record) => '/${record.serverId}',
    toJson: (m) => m,
    successStatusCodes: {200, 204},
  ),
];
```

### Step 4 — Queue records anywhere

```dart
// Queue a create
await OfflineSyncKit.queue<Order>(
  boxKey: 'create_orders',
  data: Order(item: 'Widget Pro', qty: 5),
);

// Queue an update — pass serverId so the URL suffix can use it
await OfflineSyncKit.queueRaw(
  boxKey: 'update_orders',
  payload: {'qty': 10},
  serverId: '42',
);

// Queue a delete
await OfflineSyncKit.queueRaw(
  boxKey: 'delete_orders',
  payload: {},
  serverId: '42',
);
```

### Step 5 — (Optional) Trigger sync manually

```dart
// On pull-to-refresh, "Sync now" button, or connectivity restored event
await OfflineSyncKit.triggerSync();
```

---

## API reference

### `OfflineSyncKit`

| Method | Returns | Description |
|---|---|---|
| `initialize(config, backgroundDispatcher?)` | `Future<void>` | One-time setup. Call before `runApp`. |
| `queue<T>(boxKey, data, ...)` | `Future<String>` | Serialize `T` via `toJson` and enqueue. |
| `queueRaw(boxKey, payload, ...)` | `Future<String>` | Enqueue a raw `Map` directly. |
| `triggerSync()` | `Future<SyncSummary>` | Run sync immediately on calling isolate. |
| `getPendingRecords(boxKey)` | `Future<List<SyncRecord>>` | Pending/failed records for a box. |
| `getAllRecords(boxKey)` | `Future<List<SyncRecord>>` | All records regardless of status. |
| `removeRecord(boxKey, localId)` | `Future<void>` | Delete a specific record. |
| `pendingCount()` | `Future<int>` | Total pending count across all entities. |
| `clearAll()` | `Future<void>` | Wipe all queued data (call on logout). |
| `stopBackgroundSync()` | `Future<void>` | Cancel WorkManager tasks. |

### `SyncConfig`

| Property | Type | Default | Description |
|---|---|---|---|
| `baseUrl` | `String` | required | Base URL for all API calls |
| `getAuthToken` | `Future<String?> Function()` | required | Returns Bearer token |
| `entities` | `List<SyncEntityConfig>` | required | Entities synced in order |
| `defaultHeaders` | `Map<String, String>` | `{}` | Added to every request |
| `requestTimeout` | `Duration` | `30s` | Per-request HTTP timeout |
| `backgroundSyncInterval` | `Duration` | `2h` | WorkManager frequency |
| `minBatteryLevel` | `int` | `20` | Skip sync below this % (0 = disabled) |
| `skipSyncWhenForeground` | `bool` | `true` | Pause sync when app is visible |
| `showSyncNotifications` | `bool` | `true` | Show post-cycle notifications |
| `checkVpn` | `Future<bool> Function()?` | `null` | Optional VPN check |
| `onSyncStart` | `void Function()?` | `null` | Sync cycle start callback |
| `onSyncComplete` | `void Function(int, int)?` | `null` | Success/fail count callback |

### `SyncEntityConfig<T>`

| Property | Type | Description |
|---|---|---|
| `boxKey` | `String` | Unique Hive box key. **Never rename after first release.** |
| `endpoint` | `String` | API path, e.g. `'/orders'` |
| `method` | `HttpMethod` | `get`, `post`, `put`, `patch`, `delete` |
| `toJson` | `Map<String, dynamic> Function(T)` | Serialises your model for Hive storage |
| `fromJson` | `T Function(Map)?` | Deserialises back (optional) |
| `successStatusCodes` | `Set<int>` | Defaults to `{200, 201}` |
| `extractServerId` | `String? Function(Map)?` | Reads server id from response body |
| `buildPathSuffix` | `String Function(SyncRecord)?` | Builds URL suffix, e.g. `'/${record.serverId}'` |
| `onSuccess` | `void Function(SyncResult)?` | Per-record success hook |
| `onFailure` | `void Function(SyncResult)?` | Per-record failure hook |
| `maxRetries` | `int` | Defaults to `3` |
| `extraHeaders` | `Map<String, String>?` | Entity-specific request headers |

---

## How it works

```
App foreground                      WorkManager background isolate
────────────────                    ─────────────────────────────────
OfflineSyncKit.queue()              SyncOrchestrator.run()
        │                                │
        ▼                                ├─ 1. foreground check
SyncRecord stored as                     ├─ 2. battery check
Map in Hive box                          ├─ 3. pending-data check
status: pending                          ├─ 4. connectivity check
                                         ├─ 5. auth token fetch
                                         │
                                         └─ for each SyncEntityConfig:
                                                SyncEngine.syncAll()
                                                    ├─ read pending records
                                                    ├─ HTTP request
                                                    ├─ success → delete record
                                                    └─ failure → retry / dead-letter
```

---

## Showing pending count in UI

```dart
// In a StatefulWidget
Future<void> _refresh() async {
  final count = await OfflineSyncKit.pendingCount();
  setState(() => _pendingCount = count);
}

// Show badge on a sync icon
```

## Logout / account switch

```dart
await OfflineSyncKit.clearAll();         // wipe all queued records
await OfflineSyncKit.stopBackgroundSync(); // cancel WorkManager tasks
```

---

## License

MIT — see [LICENSE](LICENSE).
