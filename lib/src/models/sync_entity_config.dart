import 'http_method.dart';
import 'sync_record.dart';
import 'sync_result.dart';

/// Configuration for one logical "entity + operation" pair
/// (e.g. create-order, update-order, delete-order are three separate configs).
///
/// Register one [SyncEntityConfig] per [SyncConfig.entities] entry.
/// Records are stored in a dedicated Hive box named [boxKey].
///
/// ### Create example
/// ```dart
/// SyncEntityConfig<Order>(
///   boxKey: 'create_orders',
///   endpoint: '/orders',
///   method: HttpMethod.post,
///   toJson: (o) => o.toJson(),
///   extractServerId: (data) => data['id']?.toString(),
///   onSuccess: (r) => print('Created: ${r.serverId}'),
///   maxRetries: 3,
/// )
/// ```
///
/// ### Update example (URL suffix contains server id)
/// ```dart
/// SyncEntityConfig<Map<String, dynamic>>(
///   boxKey: 'update_orders',
///   endpoint: '/orders',
///   method: HttpMethod.patch,
///   buildPathSuffix: (record) => '/${record.serverId}',
///   toJson: (m) => m,
/// )
/// ```
class SyncEntityConfig<T> {
  /// Unique Hive box name for this entity's pending queue.
  ///
  /// Use `snake_case`, keep it under 64 characters, and **never rename it**
  /// after your first release — renaming orphans any existing queued records.
  final String boxKey;

  /// Base API endpoint path, e.g. `'/api/v1/orders'`.
  final String endpoint;

  /// HTTP verb for this entity's sync request.
  final HttpMethod method;

  /// Converts a domain model [T] into a JSON-serialisable [Map] before it is
  /// stored in Hive. All map values must be primitives, lists, or maps.
  final Map<String, dynamic> Function(T model) toJson;

  /// Deserialises a stored [Map] back into your domain model [T].
  /// Optional — only needed if you want typed access in [onSuccess] / [onFailure].
  final T Function(Map<String, dynamic> json)? fromJson;

  /// HTTP status codes considered successful. Defaults to `{200, 201}`.
  final Set<int> successStatusCodes;

  /// Extracts the server-assigned id from the response body after a successful
  /// create operation. Return `null` if the response does not carry an id.
  final String? Function(Map<String, dynamic> responseData)? extractServerId;

  /// Builds a URL path suffix appended to [endpoint] just before each request.
  ///
  /// Example: `(record) => '/${record.serverId}'`
  /// Resulting URL: `https://api.example.com/orders/42`
  final String Function(SyncRecord record)? buildPathSuffix;

  /// Called after a successful sync. Use to update local caches or emit events.
  final void Function(SyncResult result)? onSuccess;

  /// Called after a failed sync attempt. Use to surface errors in your UI.
  final void Function(SyncResult result)? onFailure;

  /// Maximum number of retry attempts before the record is marked [SyncStatus.dead].
  /// Defaults to `3`.
  final int maxRetries;

  /// Entity-specific headers merged on top of [SyncConfig.defaultHeaders].
  final Map<String, String>? extraHeaders;

  const SyncEntityConfig({
    required this.boxKey,
    required this.endpoint,
    required this.method,
    required this.toJson,
    this.fromJson,
    this.successStatusCodes = const {200, 201},
    this.extractServerId,
    this.buildPathSuffix,
    this.onSuccess,
    this.onFailure,
    this.maxRetries = 3,
    this.extraHeaders,
  });
}
