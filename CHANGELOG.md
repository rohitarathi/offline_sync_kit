# Changelog

## 0.1.0

Initial release.

- Generic `SyncRecord` serialised as a plain `Map` in Hive — no `TypeAdapter` or `build_runner` required by consumers
- `SyncEntityConfig<T>` with `toJson`/`fromJson`, `buildPathSuffix`, `extractServerId`, `onSuccess`/`onFailure` hooks
- `SyncOrchestrator` with ordered pre-flight guards: foreground, battery, pending-data, connectivity, auth
- `SyncEngine` with per-record retry, dead-letter (`SyncStatus.dead`), and interrupt support
- `BackgroundSyncDispatcher` + `BackgroundSyncManager` for WorkManager integration
- `AppLifecycleObserver` persists foreground flag to `SharedPreferences` for background isolate access
- `SyncNotificationService` for per-cycle summary notifications
- `SyncErrorHandler` converts Dio / network exceptions to user-friendly strings
- `ConnectivityChecker` with optional VPN callback
- Full example app
- Unit tests (no Flutter binding or Hive required)
