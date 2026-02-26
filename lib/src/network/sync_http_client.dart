import 'package:dio/dio.dart';

import '../models/http_method.dart';
import '../models/sync_entity_config.dart';
import '../models/sync_record.dart';

/// Thin Dio wrapper used by [SyncEngine] to dispatch HTTP requests.
class SyncHttpClient {
  final Dio _dio;

  SyncHttpClient({
    required Duration timeout,
    Map<String, String> defaultHeaders = const {},
  }) : _dio = Dio(
          BaseOptions(
            connectTimeout: timeout,
            receiveTimeout: timeout,
            sendTimeout: timeout,
          ),
        );

  /// Sends a single [SyncRecord] according to [entityConfig] and returns the
  /// raw [Response].
  Future<Response<dynamic>> send({
    required String baseUrl,
    required SyncEntityConfig entityConfig,
    required SyncRecord record,
    required String authToken,
  }) async {
    final suffix =
        entityConfig.buildPathSuffix?.call(record) ?? record.pathSuffix ?? '';
    final url = '$baseUrl${entityConfig.endpoint}$suffix';

    final headers = <String, dynamic>{
      'Content-Type': 'application/json',
      'Authorization': authToken,
      ...?entityConfig.extraHeaders,
    };

    final options = Options(headers: headers);

    switch (entityConfig.method) {
      case HttpMethod.get:
        return _dio.get<dynamic>(url, options: options);
      case HttpMethod.post:
        return _dio.post<dynamic>(url, data: record.payload, options: options);
      case HttpMethod.put:
        return _dio.put<dynamic>(url, data: record.payload, options: options);
      case HttpMethod.patch:
        return _dio.patch<dynamic>(url, data: record.payload, options: options);
      case HttpMethod.delete:
        return _dio.delete<dynamic>(url,
            data: record.payload, options: options);
    }
  }
}
