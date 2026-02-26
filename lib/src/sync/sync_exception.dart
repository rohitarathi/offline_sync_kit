/// Thrown when a sync cycle is deliberately interrupted because the app moved
/// to the foreground while a background sync was running.
class SyncInterruptedException implements Exception {
  final String message;
  const SyncInterruptedException(this.message);

  @override
  String toString() => 'SyncInterruptedException: $message';
}

/// Thrown when a valid auth token cannot be obtained.
class SyncAuthException implements Exception {
  final String message;
  const SyncAuthException(this.message);

  @override
  String toString() => 'SyncAuthException: $message';
}

/// Thrown when neither internet nor VPN connectivity is available.
class SyncConnectivityException implements Exception {
  final String message;
  const SyncConnectivityException(this.message);

  @override
  String toString() => 'SyncConnectivityException: $message';
}
