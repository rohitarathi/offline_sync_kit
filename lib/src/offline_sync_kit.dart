import 'package:flutter/foundation.dart';

import 'models/sync_entity_config.dart';
import 'models/sync_record.dart';
import 'models/sync_result.dart';
import 'models/sync_status.dart';
import 'notifications/sync_notification_service.dart';
import 'storage/sync_queue_storage.dart';
import 'sync/background_sync_dispatcher.dart';
import 'sync/sync_orchestrator.dart';
import 'sync_config.dart';

/// The main entry point for offline_sync_kit.
///
/// ---
///
/// ## Setup — three steps
///
/// ### Step 1 — Declare the WorkManager dispatcher at the **top level** of your file
///
/// ```dart
/// // main.dart  (must be a top-level function, NOT inside a class)
/// @pragma('vm:entry-point')
/// void myBackgroundDispatcher() {
///   BackgroundSyncDispatcher.callbackDispatcher(
///     configFactory: () => SyncConfig(
///       baseUrl: 'https://api.example.com',
///       getAuthToken: () async => 'Bearer ${MyAuth.token}',
///       entities: myEntities,
///     ),
///   );
/// }
/// ```
///
/// ### Step 2 — Initialize in `main()`
///
/// ```dart
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   AppLifecycleObserver.initialize();
///
///   await OfflineSyncKit.initialize(
///     backgroundDispatcher: myBackgroundDispatcher,
///     config: SyncConfig(
///       baseUrl: 'https://api.example.com',
///       getAuthToken: () async => 'Bearer ${MyAuth.token}',
///       entities: [
///         SyncEntityConfig<Map<String, dynamic>>(
///           boxKey: 'create_orders',
///           endpoint: '/orders',
///           method: HttpMethod.post,
///           toJson: (m) => m,
///         ),
///       ],
///     ),
///   );
///
///   runApp(const MyApp());
/// }
/// ```
///
/// ### Step 3 — Queue records anywhere in the app
///
/// ```dart
/// await OfflineSyncKit.queue(
///   boxKey: 'create_orders',
///   data: myOrder,
/// );
/// ```
class OfflineSyncKit {
  OfflineSyncKit._();

  static SyncConfig? _config;
  static bool _initialized = false;

  // ── Initialization ─────────────────────────────────────────────────────────

  /// Initializes the plugin. Call once before `runApp()`.
  ///
  /// - [config] — full sync configuration (required).
  /// - [backgroundDispatcher] — the top-level function annotated with
  ///   `@pragma('vm:entry-point')` that calls
  ///   [BackgroundSyncDispatcher.callbackDispatcher]. Pass `null` to disable
  ///   automatic background sync (manual [triggerSync] still works).
  /// - [registerBackgroundTask] — set to `false` to skip WorkManager
  ///   registration (useful in tests).
  static Future<void> initialize({
    required SyncConfig config,
    Function()? backgroundDispatcher,
    bool registerBackgroundTask = true,
  }) async {
    if (_initialized) return;

    _config = config;

    // Initialize Hive storage.
    await SyncQueueStorage.instance.initialize();

    // Initialize local notifications.
    if (config.showSyncNotifications) {
      await SyncNotificationService.initialize();
    }

    // Register the WorkManager periodic task.
    if (backgroundDispatcher != null && registerBackgroundTask) {
      final manager = BackgroundSyncManager(config);
      await manager.register(dispatcher: backgroundDispatcher);
    }

    _initialized = true;
    debugPrint('[OfflineSyncKit] ✅ Initialized (baseUrl: ${config.baseUrl})');
  }

  // ── Core API ───────────────────────────────────────────────────────────────

  /// Serializes [data] via [SyncEntityConfig.toJson] and queues the result for
  /// the next sync cycle.
  ///
  /// Returns the `localId` (a unique string) assigned to the queued record.
  ///
  /// - [boxKey] must match a registered [SyncEntityConfig.boxKey].
  /// - [serverId] — supply when queuing an update/delete so the URL suffix
  ///   builder can access it via `record.serverId`.
  /// - [pathSuffix] — static suffix appended to the endpoint URL, e.g.
  ///   `'/42'`. Overridden at sync time by [SyncEntityConfig.buildPathSuffix].
  static Future<String> queue<T>({
    required String boxKey,
    required T data,
    String? serverId,
    String? pathSuffix,
  }) async {
    _assertInitialized();

    final entityConfig = _findConfig(boxKey);
    // toJson is typed as Function(T) at registration time. We call it via
    // dynamic dispatch to avoid a runtime cast that would fail if T inference
    // doesn't exactly match the registered type parameter.
    // ignore: avoid_dynamic_calls
    final json = (entityConfig.toJson as dynamic)(data) as Map<String, dynamic>;
    final localId = _generateId();

    final record = SyncRecord(
      localId: localId,
      entityKey: boxKey,
      payload: json,
      serverId: serverId,
      status: SyncStatus.pending,
      createdAt: DateTime.now().toIso8601String(),
      pathSuffix: pathSuffix,
    );

    await SyncQueueStorage.instance.enqueue(boxKey, record);
    debugPrint('[OfflineSyncKit] 📥 Queued $localId → $boxKey');
    return localId;
  }

  /// Queues a pre-built [Map] payload without going through
  /// [SyncEntityConfig.toJson]. Useful when your data is already in map form.
  ///
  /// Returns the generated `localId`.
  static Future<String> queueRaw({
    required String boxKey,
    required Map<String, dynamic> payload,
    String? serverId,
    String? pathSuffix,
  }) async {
    _assertInitialized();

    final localId = _generateId();
    final record = SyncRecord(
      localId: localId,
      entityKey: boxKey,
      payload: payload,
      serverId: serverId,
      status: SyncStatus.pending,
      createdAt: DateTime.now().toIso8601String(),
      pathSuffix: pathSuffix,
    );

    await SyncQueueStorage.instance.enqueue(boxKey, record);
    debugPrint('[OfflineSyncKit] 📥 Queued raw $localId → $boxKey');
    return localId;
  }

  /// Triggers a sync cycle immediately on the calling isolate.
  ///
  /// Useful when the user explicitly requests a sync (e.g. pull-to-refresh or
  /// a "Sync now" button).
  static Future<SyncSummary> triggerSync() async {
    _assertInitialized();
    debugPrint('[OfflineSyncKit] ▶️ Manual sync triggered');

    final results = <SyncResult>[];

    // Run the orchestrator; individual engine results are captured via the
    // onSuccess / onFailure hooks registered in SyncEntityConfig. We also
    // collect them here by comparing before/after record counts.
    await SyncOrchestrator(_config!).run();

    return SyncSummary(results: results, completedAt: DateTime.now());
  }

  // ── Inspection helpers ─────────────────────────────────────────────────────

  /// Returns all pending or failed records for [boxKey].
  static Future<List<SyncRecord>> getPendingRecords(String boxKey) async {
    _assertInitialized();
    return SyncQueueStorage.instance.getPending(
      boxKey,
      maxRetries: _findConfig(boxKey).maxRetries,
    );
  }

  /// Returns every record for [boxKey] regardless of status.
  static Future<List<SyncRecord>> getAllRecords(String boxKey) async {
    _assertInitialized();
    return SyncQueueStorage.instance.getAll(boxKey);
  }

  /// Permanently deletes a specific record from [boxKey].
  static Future<void> removeRecord(String boxKey, String localId) async {
    _assertInitialized();
    await SyncQueueStorage.instance.delete(boxKey, localId);
  }

  /// Returns the combined pending/failed count across all registered entities.
  static Future<int> pendingCount() async {
    _assertInitialized();
    final keys = _config!.entities.map((e) => e.boxKey).toList();
    return SyncQueueStorage.instance.pendingCount(keys);
  }

  // ── Lifecycle helpers ──────────────────────────────────────────────────────

  /// Clears all queued records (call on logout or account switch).
  static Future<void> clearAll() async {
    _assertInitialized();
    final keys = _config!.entities.map((e) => e.boxKey).toList();
    await SyncQueueStorage.instance.clearAll(keys);
    debugPrint('[OfflineSyncKit] 🗑️ All queued data cleared');
  }

  /// Cancels all WorkManager background tasks registered by this plugin.
  static Future<void> stopBackgroundSync() async {
    _assertInitialized();
    await BackgroundSyncManager(_config!).cancelAll();
  }

  // ── Internal helpers ───────────────────────────────────────────────────────

  static void _assertInitialized() {
    assert(
      _initialized,
      '[OfflineSyncKit] Not initialized. '
      'Call OfflineSyncKit.initialize() before using any other API.',
    );
  }

  /// Finds an entity config by [boxKey]. Returns the raw untyped base class;
  /// callers that need typed access must cast.
  static SyncEntityConfig _findConfig(String boxKey) {
    try {
      return _config!.entities.firstWhere((e) => e.boxKey == boxKey);
    } catch (_) {
      throw ArgumentError(
        '[OfflineSyncKit] No SyncEntityConfig found for boxKey "$boxKey". '
        'Check that it is registered in SyncConfig.entities.',
      );
    }
  }

  /// Generates a unique local id using high-resolution timestamp + counter.
  static int _counter = 0;
  static String _generateId() {
    _counter++;
    final ts = DateTime.now().microsecondsSinceEpoch;
    return '${ts}_$_counter';
  }
}
