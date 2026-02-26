import 'models/sync_entity_config.dart';

/// Top-level configuration for [OfflineSyncKit].
///
/// Pass one [SyncConfig] instance to [OfflineSyncKit.initialize].
class SyncConfig {
  /// Base URL prepended to every [SyncEntityConfig.endpoint],
  /// e.g. `'https://api.example.com'`.
  final String baseUrl;

  /// Async callback that returns a valid `Authorization` header value,
  /// e.g. `'Bearer eyJhbGci...'`. Called once before every sync cycle.
  ///
  /// Return `null` or an empty string to abort the cycle (user not authenticated).
  final Future<String?> Function() getAuthToken;

  /// Ordered list of entity configurations.
  ///
  /// Entities are synced sequentially in list order. If entity A must exist on
  /// the server before entity B references it, put A first.
  final List<SyncEntityConfig> entities;

  /// Headers added to every sync request. [SyncEntityConfig.extraHeaders] are
  /// merged on top per entity.
  final Map<String, String> defaultHeaders;

  /// HTTP request timeout per record. Defaults to 30 seconds.
  final Duration requestTimeout;

  /// How often WorkManager should run a background sync cycle.
  /// Defaults to every 2 hours. Android enforces a minimum of ~15 minutes.
  final Duration backgroundSyncInterval;

  /// Minimum battery percentage (0–100) required to proceed with sync.
  /// Defaults to `20`. Set to `0` to disable the battery check.
  final int minBatteryLevel;

  /// When `true` (default), the sync cycle is skipped if the app is currently
  /// in the foreground, preventing interference with the active user session.
  final bool skipSyncWhenForeground;

  /// When `true` (default), shows local notifications summarising each sync cycle.
  final bool showSyncNotifications;

  /// Unique name used for WorkManager task registration. Defaults to
  /// `'offline_sync_kit'`. Change this if you use the plugin in multiple apps.
  final String workerName;

  /// Optional VPN connectivity check. Return `true` if VPN is active and
  /// connectivity should be allowed. Leave `null` to skip the VPN check.
  final Future<bool> Function()? checkVpn;

  /// Called at the start of every sync cycle.
  final void Function()? onSyncStart;

  /// Called at the end of every sync cycle with success and failure counts.
  final void Function(int succeeded, int failed)? onSyncComplete;

  const SyncConfig({
    required this.baseUrl,
    required this.getAuthToken,
    required this.entities,
    this.defaultHeaders = const {},
    this.requestTimeout = const Duration(seconds: 30),
    this.backgroundSyncInterval = const Duration(hours: 2),
    this.minBatteryLevel = 20,
    this.skipSyncWhenForeground = true,
    this.showSyncNotifications = true,
    this.workerName = 'offline_sync_kit',
    this.checkVpn,
    this.onSyncStart,
    this.onSyncComplete,
  });
}
