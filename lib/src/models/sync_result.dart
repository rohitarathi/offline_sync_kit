/// Outcome of a single sync attempt for one [SyncRecord].
class SyncResult {
  final String localId;
  final String entityKey;
  final bool success;

  /// Server-assigned id extracted from the response body on success.
  final String? serverId;

  /// Error description when [success] is `false`.
  final String? errorMessage;

  /// HTTP status code returned by the server (0 if a network error occurred).
  final int statusCode;

  const SyncResult({
    required this.localId,
    required this.entityKey,
    required this.success,
    this.serverId,
    this.errorMessage,
    this.statusCode = 0,
  });

  factory SyncResult.success({
    required String localId,
    required String entityKey,
    String? serverId,
    int statusCode = 200,
  }) =>
      SyncResult(
        localId: localId,
        entityKey: entityKey,
        success: true,
        serverId: serverId,
        statusCode: statusCode,
      );

  factory SyncResult.failure({
    required String localId,
    required String entityKey,
    required String errorMessage,
    int statusCode = 0,
  }) =>
      SyncResult(
        localId: localId,
        entityKey: entityKey,
        success: false,
        errorMessage: errorMessage,
        statusCode: statusCode,
      );

  @override
  String toString() => 'SyncResult(success: $success, localId: $localId, '
      'statusCode: $statusCode, error: $errorMessage)';
}

/// Aggregated summary returned by [OfflineSyncKit.triggerSync].
class SyncSummary {
  final List<SyncResult> results;
  final DateTime completedAt;

  const SyncSummary({required this.results, required this.completedAt});

  int get successCount => results.where((r) => r.success).length;
  int get failureCount => results.where((r) => !r.success).length;
  bool get allSucceeded => failureCount == 0;
  bool get isEmpty => results.isEmpty;

  @override
  String toString() =>
      'SyncSummary(success: $successCount, failed: $failureCount)';
}
