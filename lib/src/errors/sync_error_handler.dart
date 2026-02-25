import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

/// Converts raw exceptions into user-friendly, non-technical error strings
/// suitable for local notifications and sync log displays.
class SyncErrorHandler {
  SyncErrorHandler._();

  /// Returns a concise user-facing message for any caught object.
  static String getMessage(dynamic error) {
    try {
      if (error is DioException) return _fromDio(error);
      if (error is SocketException) {
        return 'Network error: ${error.message}';
      }
      if (error is HttpException) {
        return 'HTTP error: ${error.message}';
      }
      if (error is FormatException) {
        return 'Invalid response format from server';
      }
      if (error is TimeoutException) {
        return 'Request timed out — please try again';
      }
      return _clean(error.toString());
    } catch (_) {
      return 'An unexpected error occurred';
    }
  }

  static String _fromDio(DioException e) {
    switch (e.type) {
      case DioExceptionType.badResponse:
        return _fromBadResponse(e);
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Connection timed out — check your internet connection';
      case DioExceptionType.connectionError:
        return _fromConnectionError(e);
      case DioExceptionType.badCertificate:
        return 'SSL certificate error — check your connection security';
      case DioExceptionType.cancel:
        return 'Request was cancelled';
      case DioExceptionType.unknown:
        return _fromUnknown(e);
    }
  }

  static String _fromBadResponse(DioException e) {
    final code = e.response?.statusCode;
    final serverMsg = _extractServerMessage(e.response?.data);

    switch (code) {
      case 400:
        return serverMsg ?? 'Bad request — please check your data';
      case 401:
        return 'Unauthorised — please log in again';
      case 403:
        return 'Access denied — insufficient permissions';
      case 404:
        return serverMsg ?? 'Resource not found on server';
      case 408:
        return 'Request timeout';
      case 409:
        return serverMsg ?? 'Conflict — record may already exist';
      case 422:
        return serverMsg ?? 'Validation error — check your input';
      case 429:
        return 'Too many requests — please wait before retrying';
      case 500:
        return 'Internal server error — please try again later';
      case 502:
        return 'Bad gateway — please try again later';
      case 503:
        return 'Service unavailable — please try again later';
      case 504:
        return 'Gateway timeout — please try again later';
      default:
        if (code != null && code >= 400 && code < 500) {
          return serverMsg ?? 'Client error ($code)';
        } else if (code != null && code >= 500) {
          return serverMsg ?? 'Server error ($code)';
        }
        return serverMsg ?? 'Unexpected server response';
    }
  }

  static String _fromConnectionError(DioException e) {
    final raw = '${e.error} ${e.message}'.toLowerCase();
    if (raw.contains('failed host lookup')) return 'No internet connection';
    if (raw.contains('network is unreachable')) return 'Network unavailable';
    if (raw.contains('connection refused')) return 'Cannot reach server';
    return 'Connection failed — check your internet connection';
  }

  static String _fromUnknown(DioException e) {
    final raw = '${e.error} ${e.message}'.toLowerCase();
    if (raw.contains('socketexception')) {
      if (raw.contains('failed host lookup')) return 'No internet connection';
      if (raw.contains('connection refused')) return 'Cannot reach server';
      if (raw.contains('timed out')) return 'Connection timed out';
      return 'Network error — check your connection';
    }
    if (raw.contains('handshakeexception') || raw.contains('ssl')) {
      return 'SSL / security error';
    }
    if (raw.contains('connection closed')) {
      return 'Connection was closed unexpectedly';
    }
    return _clean(raw);
  }

  static String? _extractServerMessage(dynamic data) {
    if (data == null) return null;
    if (data is String && data.isNotEmpty) {
      return data.length > 150 ? '${data.substring(0, 147)}...' : data;
    }
    if (data is Map) {
      const keys = [
        'message',
        'error',
        'error_description',
        'errorMessage',
        'detail',
        'details',
        'title',
        'msg',
      ];
      for (final key in keys) {
        final val = data[key];
        if (val is String && val.isNotEmpty) return val;
      }
      if (data['errors'] is List) {
        final first = (data['errors'] as List).firstOrNull;
        if (first != null) return first.toString();
      }
    }
    return null;
  }

  static String _clean(String message) {
    message = message
        .replaceFirst('Exception: ', '')
        .replaceFirst('Error: ', '')
        .replaceAll('DioException [Unknown]: null.', '')
        .replaceAll('DioException [Unknown]:', '')
        .replaceAll('DioException:', '')
        .trim();

    if (message.contains(', url=')) {
      message = message.split(', url=').first;
    }

    if (message.length > 120) return 'An error occurred — please try again';
    if (message.isEmpty || message.startsWith('Instance of')) {
      return 'An unexpected error occurred';
    }
    return message;
  }
}
