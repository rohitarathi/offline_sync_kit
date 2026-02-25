import 'package:flutter/foundation.dart';

import '../errors/sync_error_handler.dart';
import '../models/sync_entity_config.dart';
import '../models/sync_record.dart';
import '../models/sync_result.dart';
import '../models/sync_status.dart';
import '../network/sync_http_client.dart';
import '../notifications/sync_notification_service.dart';
import '../storage/sync_queue_storage.dart';
import '../sync_config.dart';
import 'sync_exception.dart';

/// Processes all pending [SyncRecord]s for a single [SyncEntityConfig].
class SyncEngine {
  final SyncConfig config;
  final SyncEntityConfig entityConfig;
  final SyncHttpClient httpClient;
  final SyncQueueStorage storage;
  final bool skipWhenForeground;
  final Future<bool> Function() isForeground;

  SyncEngine({
    required this.config,
    required this.entityConfig,
    required this.httpClient,
    required this.storage,
    required this.skipWhenForeground,
    required this.isForeground,
  });

  /// Syncs all pending records for this entity.
  ///
  /// Returns one [SyncResult] per record attempted.
  /// Throws [SyncInterruptedException] if the app moves to the foreground
  /// mid-cycle so the orchestrator can stop cleanly.
  Future<List<SyncResult>> syncAll(String authToken) async {
    final records = await storage.getPending(
      entityConfig.boxKey,
      maxRetries: entityConfig.maxRetries,
    );

    if (records.isEmpty) {
      debugPrint('[OfflineSyncKit] ${entityConfig.boxKey}: nothing to sync');
      return [];
    }

    debugPrint(
      '[OfflineSyncKit] ${entityConfig.boxKey}: '
      'syncing ${records.length} record(s)',
    );

    final results = <SyncResult>[];
    int successCount = 0;
    int failureCount = 0;

    for (final record in records) {
      // Abort if the app came back to the foreground.
      if (skipWhenForeground && await isForeground()) {
        throw SyncInterruptedException(
          'App moved to foreground — aborting ${entityConfig.boxKey} sync',
        );
      }

      final result = await _syncOne(record, authToken);
      results.add(result);
      if (result.success) {
        successCount++;
      } else {
        failureCount++;
      }
    }

    if (config.showSyncNotifications &&
        (successCount > 0 || failureCount > 0)) {
      await SyncNotificationService.showSyncSummary(
        entityLabel: entityConfig.boxKey,
        successCount: successCount,
        failureCount: failureCount,
      );
    }

    return results;
  }

  Future<SyncResult> _syncOne(SyncRecord record, String authToken) async {
    // Mark as in-progress before sending.
    await storage.update(
      entityConfig.boxKey,
      record.copyWith(
        status: SyncStatus.inProgress,
        lastAttemptAt: DateTime.now().toIso8601String(),
      ),
    );

    try {
      final response = await httpClient.send(
        baseUrl: config.baseUrl,
        entityConfig: entityConfig,
        record: record,
        authToken: authToken,
      );

      final statusCode = response.statusCode ?? 0;

      if (entityConfig.successStatusCodes.contains(statusCode)) {
        // ── Success ────────────────────────────────────────────────────────
        String? serverId;
        final data = response.data;
        if (data is Map<String, dynamic>) {
          serverId = entityConfig.extractServerId?.call(data);
        } else if (data is Map) {
          // Handle cases where Dio returns Map<dynamic, dynamic>
          final typedData = Map<String, dynamic>.from(data);
          serverId = entityConfig.extractServerId?.call(typedData);
        }

        await storage.delete(entityConfig.boxKey, record.localId);

        final result = SyncResult.success(
          localId: record.localId,
          entityKey: entityConfig.boxKey,
          serverId: serverId,
          statusCode: statusCode,
        );
        entityConfig.onSuccess?.call(result);
        debugPrint('[OfflineSyncKit] ✅ ${record.localId} synced');
        return result;
      } else {
        // ── HTTP error status ──────────────────────────────────────────────
        final errorMsg = SyncErrorHandler.getMessage(
            response.statusMessage ?? 'HTTP $statusCode');
        await _markFailed(record, errorMsg);
        final result = SyncResult.failure(
          localId: record.localId,
          entityKey: entityConfig.boxKey,
          errorMessage: errorMsg,
          statusCode: statusCode,
        );
        entityConfig.onFailure?.call(result);
        return result;
      }
    } catch (e) {
      // ── Network / Dio exception ──────────────────────────────────────────
      final errorMsg = SyncErrorHandler.getMessage(e);
      await _markFailed(record, errorMsg);
      final result = SyncResult.failure(
        localId: record.localId,
        entityKey: entityConfig.boxKey,
        errorMessage: errorMsg,
      );
      entityConfig.onFailure?.call(result);
      debugPrint('[OfflineSyncKit] ❌ ${record.localId}: $errorMsg');
      return result;
    }
  }

  Future<void> _markFailed(SyncRecord record, String errorMsg) async {
    final newCount = record.retryCount + 1;
    final dead = newCount >= entityConfig.maxRetries;
    await storage.update(
      entityConfig.boxKey,
      record.copyWith(
        status: dead ? SyncStatus.dead : SyncStatus.failed,
        retryCount: newCount,
        errorMessage: errorMsg,
        lastAttemptAt: DateTime.now().toIso8601String(),
      ),
    );
  }
}
