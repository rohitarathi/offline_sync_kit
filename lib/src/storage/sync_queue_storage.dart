import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../models/sync_record.dart';
import '../models/sync_status.dart';

/// Hive-backed persistent queue for [SyncRecord] objects.
///
/// Each [SyncEntityConfig] gets its own box, keyed by [SyncEntityConfig.boxKey].
/// Records are stored as plain [Map]s so no TypeAdapter or code-generation
/// is needed by the consumer.
class SyncQueueStorage {
  SyncQueueStorage._();

  static final SyncQueueStorage instance = SyncQueueStorage._();

  static const String _subDir = 'offline_sync_kit';
  bool _initialized = false;

  // ── Initialisation ──────────────────────────────────────────────────────────

  /// Initialises Hive. Safe to call multiple times — subsequent calls are no-ops.
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/$_subDir';
      Hive.init(path);
      _initialized = true;
      debugPrint('[OfflineSyncKit] Hive initialised at $path');
    } catch (e) {
      debugPrint('[OfflineSyncKit] Hive init error: $e');
      rethrow;
    }
  }

  // ── Internal box helpers ────────────────────────────────────────────────────

  Future<Box> _openBox(String boxKey) async {
    if (Hive.isBoxOpen(boxKey)) return Hive.box(boxKey);
    return Hive.openBox(boxKey);
  }

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Enqueues a [SyncRecord] into the box for [boxKey].
  Future<void> enqueue(String boxKey, SyncRecord record) async {
    final box = await _openBox(boxKey);
    await box.put(record.localId, record.toHive());
    debugPrint('[OfflineSyncKit] Queued ${record.localId} → $boxKey');
  }

  /// Returns records from [boxKey] that are pending or failed and have not yet
  /// exceeded [maxRetries].
  Future<List<SyncRecord>> getPending(
    String boxKey, {
    int maxRetries = 3,
  }) async {
    final box = await _openBox(boxKey);
    final results = <SyncRecord>[];
    for (final raw in box.values) {
      final record = SyncRecord.fromHive(raw as Map);
      final isRetryable = record.status == SyncStatus.pending ||
          record.status == SyncStatus.failed;
      if (isRetryable && record.retryCount < maxRetries) {
        results.add(record);
      }
    }
    return results;
  }

  /// Returns every record from [boxKey] regardless of status.
  Future<List<SyncRecord>> getAll(String boxKey) async {
    final box = await _openBox(boxKey);
    return box.values.map((raw) => SyncRecord.fromHive(raw as Map)).toList();
  }

  /// Persists an updated [SyncRecord] in-place (same [localId] key).
  Future<void> update(String boxKey, SyncRecord record) async {
    final box = await _openBox(boxKey);
    await box.put(record.localId, record.toHive());
  }

  /// Removes a successfully synced record from [boxKey].
  Future<void> delete(String boxKey, String localId) async {
    final box = await _openBox(boxKey);
    await box.delete(localId);
  }

  /// Returns the combined count of pending/failed records across [boxKeys].
  Future<int> pendingCount(List<String> boxKeys) async {
    int total = 0;
    for (final key in boxKeys) {
      final box = await _openBox(key);
      for (final raw in box.values) {
        final record = SyncRecord.fromHive(raw as Map);
        if (record.status == SyncStatus.pending ||
            record.status == SyncStatus.failed) {
          total++;
        }
      }
    }
    return total;
  }

  /// Returns `true` when at least one pending record exists across [boxKeys].
  Future<bool> hasPendingData(List<String> boxKeys) async =>
      await pendingCount(boxKeys) > 0;

  /// Deletes all records from [boxKey].
  Future<void> clearBox(String boxKey) async {
    final box = await _openBox(boxKey);
    await box.clear();
  }

  /// Deletes all records across every box in [boxKeys].
  Future<void> clearAll(List<String> boxKeys) async {
    for (final key in boxKeys) {
      await clearBox(key);
    }
  }

  /// Gracefully closes all open Hive boxes.
  Future<void> closeAll() async {
    await Hive.close();
  }
}
