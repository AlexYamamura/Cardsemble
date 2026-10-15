import 'dart:convert';
import 'package:http/http.dart' as http;
import '../error/app_exception.dart';
import '../error/failure.dart';

class ApiClient {
  ApiClient({
    required String baseUrl,
    required String? Function() accessTokenProvider,
    http.Client? client,
  })  : _baseUrl = baseUrl.replaceFirst(RegExp(r'/+$'), ''),
        _accessTokenProvider = accessTokenProvider,
        _client = client ?? http.Client();

  final String _baseUrl;
  final String? Function() _accessTokenProvider;
  final http.Client _client;

  String? _getAccessToken() {
    final token = _accessTokenProvider();
    if (token == null || token.isEmpty) {
      throw const AuthException('Your session has expired. Sign in again.');
    }
    return token;
  }

  Map<String, String> _headers() {
    final token = _getAccessToken();
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  void _checkResponse(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      dynamic decoded;
      try {
        decoded = jsonDecode(response.body);
      } on FormatException {
        throw NetworkException(
          'The service returned an invalid response (HTTP ${response.statusCode}).',
        );
      }
      final detail = decoded is Map<String, dynamic>
          ? decoded['detail']?.toString()
          : null;
      throw NetworkException(
        detail ?? 'Request failed (HTTP ${response.statusCode}).',
      );
    }
  }

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) async {
    final response = await _client.post(
      Uri.parse('$_baseUrl$path'),
      headers: _headers(),
      body: jsonEncode(body),
    );
    _checkResponse(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> patch(String path, Map<String, dynamic> body) async {
    final response = await _client.patch(
      Uri.parse('$_baseUrl$path'),
      headers: _headers(),
      body: jsonEncode(body),
    );
    _checkResponse(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> delete(String path) async {
    final response = await _client.delete(
      Uri.parse('$_baseUrl$path'),
      headers: _headers(),
    );
    _checkResponse(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> get(String path) async {
    final response = await _client.get(
      Uri.parse('$_baseUrl$path'),
      headers: _headers(),
    );
    _checkResponse(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Result<Map<String, dynamic>>> safePost(String path, Map<String, dynamic> body) async {
    try {
      final result = await post(path, body);
      return Success(result);
    } on AppException catch (e) {
      return FailureResult(_mapException(e));
    } catch (e) {
      return FailureResult(UnknownFailure(e.toString()));
    }
  }

  Future<Result<Map<String, dynamic>>> safeGet(String path) async {
    try {
      final result = await get(path);
      return Success(result);
    } on AppException catch (e) {
      return FailureResult(_mapException(e));
    } catch (e) {
      return FailureResult(UnknownFailure(e.toString()));
    }
  }

  Future<Result<Map<String, dynamic>>> safePatch(String path, Map<String, dynamic> body) async {
    try {
      final result = await patch(path, body);
      return Success(result);
    } on AppException catch (e) {
      return FailureResult(_mapException(e));
    } catch (e) {
      return FailureResult(UnknownFailure(e.toString()));
    }
  }

  Future<Result<Map<String, dynamic>>> safeDelete(String path) async {
    try {
      final result = await delete(path);
      return Success(result);
    } on AppException catch (e) {
      return FailureResult(_mapException(e));
    } catch (e) {
      return FailureResult(UnknownFailure(e.toString()));
    }
  }

  Failure _mapException(AppException e) {
    return switch (e) {
      AuthException() => AuthFailure(e.message, e.code),
      NetworkException() => NetworkFailure(e.message, e.code),
      ValidationException() => ValidationFailure(e.message, e.code),
      DatabaseException() => DatabaseFailure(e.message, e.code),
      NotFoundException() => NotFoundFailure(e.message, e.code),
      PermissionException() => PermissionFailure(e.message, e.code),
      ConfigurationException() => ConfigurationFailure(e.message, e.code),
      _ => UnknownFailure(e.message, e.code),
    };
  }

  void dispose() {
    _client.close();
  }
}

List<Map<String, dynamic>> extractRecords(Map<String, dynamic> payload, String key) {
  final value = payload[key];
  if (value is! List) {
    throw NetworkException('The service response is missing "$key".');
  }
  return value
      .map((record) {
        if (record is! Map<String, dynamic>) {
          throw NetworkException('The service returned an invalid "$key" row.');
        }
        return record;
      })
      .toList(growable: false);
}