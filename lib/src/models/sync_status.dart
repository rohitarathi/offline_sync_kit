/// Lifecycle state of a queued [SyncRecord].
enum SyncStatus {
  /// Waiting to be sent to the server.
  pending,

  /// Currently being transmitted.
  inProgress,

  /// Successfully acknowledged by the server (record deleted from queue).
  synced,

  /// Last attempt failed; will be retried on the next cycle.
  failed,

  /// Permanently failed after exceeding [SyncEntityConfig.maxRetries].
  dead,
}
