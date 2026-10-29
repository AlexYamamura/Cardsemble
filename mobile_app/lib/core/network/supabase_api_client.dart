import 'dart:convert';
import 'package:http/http.dart' as http;
import '../error/app_exception.dart';
import '../error/failure.dart';

class SupabaseApiClient {
  SupabaseApiClient({
    required String baseUrl,
    required String? Function() accessTokenProvider,
    Future<String?> Function()? refreshAccessToken,
    http.Client? client,
  })  : _baseUrl = baseUrl.replaceFirst(RegExp(r'/+$'), ''),
        _accessTokenProvider = accessTokenProvider,
        _refreshAccessToken = refreshAccessToken,
        _client = client ?? http.Client();

  final String _baseUrl;
  final String? Function() _accessTokenProvider;
  /// Attempts to obtain a fresh access token (for example via Supabase's
  /// refresh-session endpoint) when a request comes back 401. May return null
  /// when there is no refreshable session (for example the refresh token is
  /// also expired or revoked).
  final Future<String?> Function()? _refreshAccessToken;
  final http.Client _client;

  String _getAccessToken() {
    final token = _accessTokenProvider();
    if (token == null || token.isEmpty) {
      throw const AuthException('Your session has expired. Sign in again.');
    }
    return token;
  }

  /// Performs a single refresh of the access token. Swallows errors so a
  /// non-refreshable session (expired or revoked refresh token) simply falls
  /// through to surfacing the original 401 to the caller.
  Future<String?> _tryRefreshAccessToken() async {
    if (_refreshAccessToken == null) return null;
    final refresh = _refreshAccessToken;
    try {
      return await refresh();
    } catch (_) {
      return null;
    }
  }

  Map<String, String> _headers(String token) {
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

  /// Sends [send] with the current access token. On a 401 response it attempts
  /// to refresh the access token once and retries the request; otherwise the
  /// original response (success or error) is returned/raised as normal.
  Future<Map<String, dynamic>> _request(
    Future<http.Response> Function(String token) send,
  ) async {
    final token = _getAccessToken();
    final response = await send(token);

    if (response.statusCode == 401) {
      final refreshed = await _tryRefreshAccessToken();
      if (refreshed != null) {
        final String fresh = refreshed;
        final retried = await send(fresh);
        _checkResponse(retried);
        return jsonDecode(retried.body) as Map<String, dynamic>;
      }
    }

    _checkResponse(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) async {
    final response = await _request((token) => _client.post(
      Uri.parse('$_baseUrl$path'),
      headers: _headers(token),
      body: jsonEncode(body),
    ));
    return response;
  }

  Future<Map<String, dynamic>> patch(String path, Map<String, dynamic> body) async {
    final response = await _request((token) => _client.patch(
      Uri.parse('$_baseUrl$path'),
      headers: _headers(token),
      body: jsonEncode(body),
    ));
    return response;
  }

  Future<Map<String, dynamic>> delete(String path) async {
    final response = await _request((token) => _client.delete(
      Uri.parse('$_baseUrl$path'),
      headers: _headers(token),
    ));
    return response;
  }

  Future<Map<String, dynamic>> get(String path) async {
    final response = await _request((token) => _client.get(
      Uri.parse('$_baseUrl$path'),
      headers: _headers(token),
    ));
    return response;
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
