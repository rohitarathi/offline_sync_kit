import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../storage/sync_queue_storage.dart';
import '../sync_config.dart';
import 'sync_orchestrator.dart';

/// Holds the [SyncConfig] reference used by the background callback.
///
/// ⚠️ **Isolate limitation**: WorkManager runs the callback in a new Dart
/// isolate. Memory is NOT shared between the main isolate and the background
/// isolate. [setConfig] must therefore be called inside
/// [callbackDispatcher] itself — not from the main isolate.
///
/// The recommended pattern is to have the consumer re-supply the config inside
/// the callback via a factory function:
///
/// ```dart
/// // top of main.dart
/// @pragma('vm:entry-point')
/// void myDispatcher() {
///   BackgroundSyncDispatcher.callbackDispatcher(
///     configFactory: () => SyncConfig(
///       baseUrl: 'https://api.example.com',
///       getAuthToken: () async => await MyAuthService.getToken(),
///       entities: myEntities,
///     ),
///   );
/// }
/// ```
class BackgroundSyncDispatcher {
  BackgroundSyncDispatcher._();

  /// The entry point registered with [Workmanager.initialize].
  ///
  /// [configFactory] must return a fully configured [SyncConfig].
  /// It is called once per WorkManager invocation inside the background isolate.
  static void callbackDispatcher({
    required SyncConfig Function() configFactory,
  }) {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();

    Workmanager().executeTask((taskName, inputData) async {
      debugPrint('[OfflineSyncKit] 🔄 WorkManager task: $taskName');

      try {
        await SyncQueueStorage.instance.initialize();
        final config = configFactory();
        final success = await SyncOrchestrator(config).run();
        return success;
      } catch (e, st) {
        debugPrint('[OfflineSyncKit] ❌ Background task error: $e\n$st');
        return false;
      }
    });
  }
}

/// Registers and cancels WorkManager tasks for [OfflineSyncKit].
class BackgroundSyncManager {
  final SyncConfig config;

  const BackgroundSyncManager(this.config);

  /// Initialises WorkManager with [dispatcher] and registers a sync task.
  ///
  /// In debug mode a one-off task (1-minute delay) is registered for easy
  /// testing. In release mode a periodic task fires every
  /// [SyncConfig.backgroundSyncInterval].
  Future<void> register({required Function() dispatcher}) async {
    await Workmanager().initialize(dispatcher, isInDebugMode: kDebugMode);

    final inputData = <String, dynamic>{'_worker': config.workerName};
    final constraints = Constraints(
      networkType: NetworkType.connected,
      requiresBatteryNotLow: config.minBatteryLevel > 0,
    );

    if (kDebugMode) {
      await Workmanager().registerOneOffTask(
        '${config.workerName}_debug',
        config.workerName,
        initialDelay: const Duration(minutes: 1),
        existingWorkPolicy: ExistingWorkPolicy.replace,
        inputData: inputData,
        constraints: constraints,
      );
      debugPrint('[OfflineSyncKit] 🧪 Debug one-off task registered');
      return;
    }

    await Workmanager().registerPeriodicTask(
      config.workerName,
      config.workerName,
      frequency: config.backgroundSyncInterval,
      existingWorkPolicy: ExistingWorkPolicy.keep,
      initialDelay: const Duration(minutes: 1),
      inputData: inputData,
      constraints: constraints,
    );

    debugPrint(
      '[OfflineSyncKit] 🚀 Periodic task registered '
      '(every ${config.backgroundSyncInterval.inMinutes} min)',
    );
  }

  /// Cancels all WorkManager tasks registered by this plugin.
  Future<void> cancelAll() async {
    await Workmanager().cancelByUniqueName(config.workerName);
    await Workmanager().cancelByUniqueName('${config.workerName}_debug');
    debugPrint('[OfflineSyncKit] 🛑 Background tasks cancelled');
  }
}
