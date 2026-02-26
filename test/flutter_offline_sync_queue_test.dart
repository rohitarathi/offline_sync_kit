import 'package:flutter_offline_sync_queue/flutter_offline_sync_queue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // ── SyncRecord ─────────────────────────────────────────────────────────────

  group('SyncRecord', () {
    late SyncRecord record;

    setUp(() {
      record = SyncRecord(
        localId: 'test-123',
        entityKey: 'create_orders',
        payload: {'item': 'Widget', 'qty': 5},
        status: SyncStatus.pending,
        createdAt: '2024-01-01T00:00:00.000Z',
        retryCount: 0,
      );
    });

    test('copyWith preserves unchanged fields', () {
      final copy = record.copyWith();
      expect(copy.localId, record.localId);
      expect(copy.entityKey, record.entityKey);
      expect(copy.payload, record.payload);
      expect(copy.status, record.status);
      expect(copy.retryCount, record.retryCount);
    });

    test('copyWith updates only specified fields', () {
      final failed = record.copyWith(
        status: SyncStatus.failed,
        retryCount: 1,
        errorMessage: 'Network error',
      );
      expect(failed.status, SyncStatus.failed);
      expect(failed.retryCount, 1);
      expect(failed.errorMessage, 'Network error');
      expect(failed.localId, record.localId); // unchanged
      expect(failed.payload, record.payload); // unchanged
    });

    test('toHive and fromHive round-trip', () {
      final map = record.toHive();
      final restored = SyncRecord.fromHive(map);
      expect(restored.localId, record.localId);
      expect(restored.entityKey, record.entityKey);
      expect(restored.payload, record.payload);
      expect(restored.status, record.status);
      expect(restored.retryCount, record.retryCount);
      expect(restored.createdAt, record.createdAt);
    });

    test('toHive stores status as int index', () {
      final map = record.toHive();
      expect(map['status'], SyncStatus.pending.index);
    });

    test('fromHive with all optional fields null', () {
      final map = {
        'localId': 'abc',
        'entityKey': 'orders',
        'payload': <String, dynamic>{},
        'serverId': null,
        'status': SyncStatus.pending.index,
        'createdAt': '2024-01-01T00:00:00.000Z',
        'lastAttemptAt': null,
        'errorMessage': null,
        'retryCount': 0,
        'pathSuffix': null,
      };
      final r = SyncRecord.fromHive(map);
      expect(r.serverId, isNull);
      expect(r.errorMessage, isNull);
      expect(r.pathSuffix, isNull);
    });
  });

  // ── SyncStatus ─────────────────────────────────────────────────────────────

  group('SyncStatus', () {
    test('all values have stable indices', () {
      expect(SyncStatus.pending.index, 0);
      expect(SyncStatus.inProgress.index, 1);
      expect(SyncStatus.synced.index, 2);
      expect(SyncStatus.failed.index, 3);
      expect(SyncStatus.dead.index, 4);
    });
  });

  // ── HttpMethod ─────────────────────────────────────────────────────────────

  group('HttpMethod', () {
    test('value returns uppercase name', () {
      expect(HttpMethod.get.value, 'GET');
      expect(HttpMethod.post.value, 'POST');
      expect(HttpMethod.put.value, 'PUT');
      expect(HttpMethod.patch.value, 'PATCH');
      expect(HttpMethod.delete.value, 'DELETE');
    });
  });

  // ── SyncResult ─────────────────────────────────────────────────────────────

  group('SyncResult', () {
    test('success factory sets correct fields', () {
      final r = SyncResult.success(
        localId: 'x',
        entityKey: 'orders',
        serverId: '42',
        statusCode: 201,
      );
      expect(r.success, isTrue);
      expect(r.serverId, '42');
      expect(r.statusCode, 201);
      expect(r.errorMessage, isNull);
    });

    test('failure factory sets correct fields', () {
      final r = SyncResult.failure(
        localId: 'x',
        entityKey: 'orders',
        errorMessage: 'Server error',
        statusCode: 500,
      );
      expect(r.success, isFalse);
      expect(r.errorMessage, 'Server error');
      expect(r.statusCode, 500);
      expect(r.serverId, isNull);
    });
  });

  // ── SyncSummary ────────────────────────────────────────────────────────────

  group('SyncSummary', () {
    test('counts successes and failures correctly', () {
      final summary = SyncSummary(
        results: [
          SyncResult.success(localId: '1', entityKey: 'a'),
          SyncResult.success(localId: '2', entityKey: 'a'),
          SyncResult.failure(localId: '3', entityKey: 'a', errorMessage: 'err'),
        ],
        completedAt: DateTime.now(),
      );
      expect(summary.successCount, 2);
      expect(summary.failureCount, 1);
      expect(summary.allSucceeded, isFalse);
    });

    test('allSucceeded is true when no failures', () {
      final summary = SyncSummary(
        results: [
          SyncResult.success(localId: '1', entityKey: 'a'),
        ],
        completedAt: DateTime.now(),
      );
      expect(summary.allSucceeded, isTrue);
    });

    test('isEmpty when results list is empty', () {
      final summary = SyncSummary(results: [], completedAt: DateTime.now());
      expect(summary.isEmpty, isTrue);
      expect(summary.successCount, 0);
      expect(summary.failureCount, 0);
    });
  });

  // ── SyncErrorHandler ───────────────────────────────────────────────────────

  group('SyncErrorHandler', () {
    test('handles plain exception', () {
      final msg =
          SyncErrorHandler.getMessage(Exception('something went wrong'));
      expect(msg, isA<String>());
      expect(msg.isNotEmpty, isTrue);
    });

    test('handles string input', () {
      final msg = SyncErrorHandler.getMessage('connection refused');
      expect(msg, isA<String>());
    });

    test('never returns empty string', () {
      for (final input in [null, '', 'Instance of SomeClass']) {
        final msg = SyncErrorHandler.getMessage(input);
        expect(msg.isNotEmpty, isTrue,
            reason: 'Expected non-empty message for input: $input');
      }
    });
  });

  // ── SyncEntityConfig ───────────────────────────────────────────────────────

  group('SyncEntityConfig', () {
    test('toJson converts model correctly', () {
      final config = SyncEntityConfig<Map<String, dynamic>>(
        boxKey: 'test_box',
        endpoint: '/test',
        method: HttpMethod.post,
        toJson: (m) => m,
      );
      final result = config.toJson({'key': 'value'});
      expect(result['key'], 'value');
    });

    test('default values are correct', () {
      final config = SyncEntityConfig<Map<String, dynamic>>(
        boxKey: 'test_box',
        endpoint: '/test',
        method: HttpMethod.post,
        toJson: (m) => m,
      );
      expect(config.maxRetries, 3);
      expect(config.successStatusCodes, {200, 201});
      expect(config.extraHeaders, isNull);
      expect(config.fromJson, isNull);
      expect(config.onSuccess, isNull);
      expect(config.onFailure, isNull);
    });
  });

  // ── SyncConfig ─────────────────────────────────────────────────────────────

  group('SyncConfig', () {
    test('defaults are sane', () {
      final config = SyncConfig(
        baseUrl: 'https://example.com',
        getAuthToken: () async => 'token',
        entities: [],
      );
      expect(config.minBatteryLevel, 20);
      expect(config.skipSyncWhenForeground, isTrue);
      expect(config.showSyncNotifications, isTrue);
      expect(config.workerName, 'offline_sync_kit');
      expect(config.requestTimeout, const Duration(seconds: 30));
      expect(config.backgroundSyncInterval, const Duration(hours: 2));
    });
  });
}
