/// offline_sync_kit
///
/// Offline-first background sync for Flutter.
///
/// ## Quick start
///
/// ```dart
/// // 1. Top-level dispatcher (must be top-level, not inside a class)
/// @pragma('vm:entry-point')
/// void myDispatcher() => BackgroundSyncDispatcher.callbackDispatcher();
///
/// // 2. Initialize once in main()
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   AppLifecycleObserver.initialize();
///
///   await OfflineSyncKit.initialize(
///     backgroundDispatcher: myDispatcher,
///     config: SyncConfig(
///       baseUrl: 'https://api.example.com',
///       getAuthToken: () async => 'Bearer <token>',
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
///
/// // 3. Queue a record anywhere in the app
/// await OfflineSyncKit.queue(
///   boxKey: 'create_orders',
///   data: {'item': 'Widget A', 'qty': 3},
/// );
/// ```
library offline_sync_kit;

export 'src/offline_sync_kit.dart';
export 'src/sync_config.dart';

export 'src/models/http_method.dart';
export 'src/models/sync_entity_config.dart';
export 'src/models/sync_record.dart';
export 'src/models/sync_result.dart';
export 'src/models/sync_status.dart';

export 'src/storage/sync_queue_storage.dart';

export 'src/network/connectivity_checker.dart';
export 'src/network/sync_http_client.dart';

export 'src/sync/background_sync_dispatcher.dart';
export 'src/sync/sync_engine.dart';
export 'src/sync/sync_exception.dart';
export 'src/sync/sync_orchestrator.dart';

export 'src/lifecycle/app_lifecycle_observer.dart';
export 'src/notifications/sync_notification_service.dart';
export 'src/errors/sync_error_handler.dart';
