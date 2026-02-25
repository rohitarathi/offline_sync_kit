import 'sync_status.dart';

/// Generic envelope stored in Hive for every queued offline operation.
///
/// You never construct this directly — use [OfflineSyncKit.queue] or
/// [OfflineSyncKit.queueRaw] instead.
///
/// The record is identified by [localId] (a UUID generated at queue time).
/// After a successful server create, [serverId] is populated from the response
/// and the record is deleted from the queue.
class SyncRecord {
  /// UUID generated locally at queue time.
  final String localId;

  /// Matches the [SyncEntityConfig.boxKey] that owns this record.
  final String entityKey;

  /// JSON payload serialised from your domain model via [SyncEntityConfig.toJson].
  final Map<String, dynamic> payload;

  /// Server-assigned id, populated after a successful create response.
  /// `null` for update/delete operations until first sync.
  String? serverId;

  /// Current lifecycle state of this record.
  SyncStatus status;

  /// ISO-8601 timestamp of when this record was queued.
  final String createdAt;

  /// ISO-8601 timestamp of the last sync attempt; `null` if never attempted.
  String? lastAttemptAt;

  /// Human-readable error message from the last failed attempt.
  String? errorMessage;

  /// Number of failed sync attempts so far.
  int retryCount;

  /// Optional URL path suffix, e.g. `'/42'`, appended to the endpoint when
  /// syncing. Useful for PATCH / DELETE where the URL contains the server id.
  String? pathSuffix;

  SyncRecord({
    required this.localId,
    required this.entityKey,
    required this.payload,
    this.serverId,
    this.status = SyncStatus.pending,
    required this.createdAt,
    this.lastAttemptAt,
    this.errorMessage,
    this.retryCount = 0,
    this.pathSuffix,
  });

  /// Returns a new [SyncRecord] with only the supplied fields replaced.
  SyncRecord copyWith({
    String? serverId,
    SyncStatus? status,
    String? lastAttemptAt,
    String? errorMessage,
    int? retryCount,
    String? pathSuffix,
  }) {
    return SyncRecord(
      localId: localId,
      entityKey: entityKey,
      payload: payload,
      serverId: serverId ?? this.serverId,
      status: status ?? this.status,
      createdAt: createdAt,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      errorMessage: errorMessage ?? this.errorMessage,
      retryCount: retryCount ?? this.retryCount,
      pathSuffix: pathSuffix ?? this.pathSuffix,
    );
  }

  /// Serialises this record to a plain [Map] for Hive storage.
  Map<String, dynamic> toHive() => {
        'localId': localId,
        'entityKey': entityKey,
        'payload': payload,
        'serverId': serverId,
        'status': status.index,
        'createdAt': createdAt,
        'lastAttemptAt': lastAttemptAt,
        'errorMessage': errorMessage,
        'retryCount': retryCount,
        'pathSuffix': pathSuffix,
      };

  /// Deserialises a [SyncRecord] from a Hive [Map].
  factory SyncRecord.fromHive(Map<dynamic, dynamic> map) {
    return SyncRecord(
      localId: map['localId'] as String,
      entityKey: map['entityKey'] as String,
      payload: Map<String, dynamic>.from(map['payload'] as Map),
      serverId: map['serverId'] as String?,
      status: SyncStatus.values[map['status'] as int],
      createdAt: map['createdAt'] as String,
      lastAttemptAt: map['lastAttemptAt'] as String?,
      errorMessage: map['errorMessage'] as String?,
      retryCount: map['retryCount'] as int,
      pathSuffix: map['pathSuffix'] as String?,
    );
  }

  @override
  String toString() => 'SyncRecord(localId: $localId, entityKey: $entityKey, '
      'status: $status, retryCount: $retryCount)';
}
