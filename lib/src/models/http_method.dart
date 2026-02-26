/// HTTP verb used when syncing a queued record to the server.
enum HttpMethod {
  get,
  post,
  put,
  patch,
  delete;

  /// Returns the uppercase string representation, e.g. `'POST'`.
  String get value => name.toUpperCase();
}
