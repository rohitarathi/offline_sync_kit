import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';

import '../errors/sync_error_handler.dart';
import '../lifecycle/app_lifecycle_observer.dart';
import '../models/sync_result.dart';
import '../network/connectivity_checker.dart';
import '../network/sync_http_client.dart';
import '../notifications/sync_notification_service.dart';
import '../storage/sync_queue_storage.dart';
import '../sync_config.dart';
import 'sync_engine.dart';
import 'sync_exception.dart';

/// Orchestrates a full sync cycle: runs pre-flight checks then delegates to
/// a [SyncEngine] for each registered [SyncEntityConfig].
class SyncOrchestrator {
  final SyncConfig config;

  SyncOrchestrator(this.config);

  /// Runs a complete sync cycle.
  ///
  /// Returns `true` even for partial failures (WorkManager should still
  /// consider the task successful so it reschedules normally).
  /// Returns `false` only on fatal failures such as missing auth.
  Future<bool> run() async {
    debugPrint('[OfflineSyncKit] 🚀 Sync cycle starting');

    try {
      // ── 1. Foreground guard ──────────────────────────────────────────────
      if (config.skipSyncWhenForeground) {
        final isFg = await AppLifecycleObserver.isAppForeground();
        if (isFg) {
          debugPrint('[OfflineSyncKit] 🛑 App in foreground — skipping sync');
          return true;
        }
      }

      // ── 2. Battery guard ─────────────────────────────────────────────────
      if (config.minBatteryLevel > 0) {
        final battery = Battery();
        final level = await battery.batteryLevel;
        final state = await battery.batteryState;
        final isCharging =
            state == BatteryState.charging || state == BatteryState.full;
        if (!isCharging && level < config.minBatteryLevel) {
          debugPrint(
            '[OfflineSyncKit] 🔋 Battery at $level% < '
            '${config.minBatteryLevel}% — skipping sync',
          );
          return true;
        }
      }

      // ── 3. Pending-data check ────────────────────────────────────────────
      final boxKeys = config.entities.map((e) => e.boxKey).toList();
      if (!await SyncQueueStorage.instance.hasPendingData(boxKeys)) {
        debugPrint('[OfflineSyncKit] ℹ️ No pending data — exiting early');
        return true;
      }

      // ── 4. Connectivity check ────────────────────────────────────────────
      final checker = ConnectivityChecker(checkVpn: config.checkVpn);
      if (!await checker.isReady()) {
        if (config.showSyncNotifications) {
          await SyncNotificationService.show(
            'Sync Skipped',
            'No internet connection — will retry automatically.',
          );
        }
        return true;
      }

      // ── 5. Auth token ────────────────────────────────────────────────────
      final token = await config.getAuthToken();
      if (token == null || token.isEmpty) {
        debugPrint('[OfflineSyncKit] 🔐 No auth token — aborting');
        throw const SyncAuthException('Could not obtain a valid auth token');
      }

      // ── 6. Sync each entity sequentially ─────────────────────────────────
      config.onSyncStart?.call();

      final httpClient = SyncHttpClient(
        timeout: config.requestTimeout,
        defaultHeaders: config.defaultHeaders,
      );

      final allResults = <SyncResult>[];

      for (final entityConfig in config.entities) {
        final engine = SyncEngine(
          config: config,
          entityConfig: entityConfig,
          httpClient: httpClient,
          storage: SyncQueueStorage.instance,
          skipWhenForeground: config.skipSyncWhenForeground,
          isForeground: AppLifecycleObserver.isAppForeground,
        );
        final results = await engine.syncAll(token);
        allResults.addAll(results);
      }

      final successes = allResults.where((r) => r.success).length;
      final failures = allResults.where((r) => !r.success).length;

      config.onSyncComplete?.call(successes, failures);
      debugPrint(
        '[OfflineSyncKit] 🎉 Cycle complete — ✅ $successes  ❌ $failures',
      );
      return true;
    } on SyncInterruptedException catch (e) {
      debugPrint('[OfflineSyncKit] ⚠️ Interrupted: $e');
      return true;
    } on SyncAuthException catch (e) {
      debugPrint('[OfflineSyncKit] 🔐 Auth error: $e');
      return false;
    } catch (e, st) {
      debugPrint('[OfflineSyncKit] ❌ Unexpected error: $e\n$st');
      if (config.showSyncNotifications) {
        await SyncNotificationService.show(
          'Sync Failed',
          SyncErrorHandler.getMessage(e),
        );
      }
      return false;
    }
  }
}
