import 'dart:math';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthException;
import 'package:cardsemble/core/core.dart';
import 'package:cardsemble/features/device_capture/domain/device_capture_domain.dart';

class DeviceCaptureRepositoryImpl implements DeviceCaptureRepository {
  DeviceCaptureRepositoryImpl({
    required SupabaseClient supabase,
  }) : _supabase = supabase;

  final SupabaseClient _supabase;
  static const _channel = MethodChannel('com.plaidtest.cardsemble/google_pay_capture');

  @override
  Future<Result<DeviceCaptureCredentials>> createGooglePayDeviceToken(String personId) async {
    try {
      final session = _supabase.auth.currentSession;
      if (session == null || session.accessToken.isEmpty) {
        return const FailureResult(AuthFailure('Your session has expired. Sign in again.'));
      }

      final expiresAt = session.expiresAt;
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      if (expiresAt != null && expiresAt < now) {
        try {
          final refreshed = await _supabase.auth.refreshSession();
          final refreshedSession = refreshed.session;
          if (refreshedSession == null || refreshedSession.accessToken.isEmpty) {
            return const FailureResult(AuthFailure('Your session has expired. Sign in again.'));
          }
        } catch (error) {
          return FailureResult(AuthFailure('Could not refresh session: $error'));
        }
      }

      final userId = session.user.id;

      try {
        await _supabase
            .from('household_members')
            .select('user_id')
            .eq('user_id', userId)
            .eq('user_id', personId)
            .limit(1);
      } catch (error) {
        return FailureResult(DatabaseFailure('Could not verify household member: $error'));
      }

      final deviceToken = _generateSecureToken();
      final hash = sha256.convert(utf8.encode(deviceToken)).toString();

      try {
        final data = await _supabase.from('device_tokens').insert({
          'user_id': userId,
          'person_id': personId,
          'device_label': 'Android Google Pay',
          'platform': 'android_google_pay',
          'token_hash': hash,
        }).select('id');
        final dataRow = (data as List);
        if (dataRow.isEmpty) {
          return const FailureResult(DatabaseFailure('Could not create device key.'));
        }
        return Success(DeviceCaptureCredentials(
          id: dataRow[0]['id'] as String,
          token: deviceToken,
        ));
      } catch (error) {
        return FailureResult(DatabaseFailure('Could not create device key: $error'));
      }
    } catch (error) {
      return FailureResult(UnknownFailure('Could not create device token: $error'));
    }
  }

  static String _generateSecureToken() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-';
    final random = Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < 43; i++) {
      buffer.write(chars[random.nextInt(chars.length)]);
    }
    return buffer.toString();
  }

  @override
  Future<Result<void>> revokeDeviceToken(String deviceId) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        return const FailureResult(AuthFailure('Your session has expired. Sign in again.'));
      }
      await _supabase
          .from('device_tokens')
          .update({'revoked_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', deviceId)
          .eq('user_id', userId)
          .isFilter('revoked_at', null);
      return const Success(null);
    } catch (error) {
      return FailureResult(DatabaseFailure('Could not revoke device key: $error'));
    }
  }

  @override
  Future<Result<bool>> isConfigured() async {
    try {
      final result = await _channel.invokeMethod<bool>('isConfigured');
      return Success(result ?? false);
    } catch (error) {
      return FailureResult(UnknownFailure('Could not check capture config: $error'));
    }
  }

  @override
  Future<Result<bool>> hasNotificationAccess() async {
    try {
      final result = await _channel.invokeMethod<bool>('hasNotificationAccess');
      return Success(result ?? false);
    } catch (error) {
      return FailureResult(UnknownFailure('Could not check notification access: $error'));
    }
  }

  @override
  Future<Result<void>> openNotificationAccessSettings() async {
    try {
      await _channel.invokeMethod<void>('openNotificationAccessSettings');
      return const Success(null);
    } catch (error) {
      return FailureResult(UnknownFailure('Could not open settings: $error'));
    }
  }

  @override
  Future<Result<bool?>> sendTestNotification() async {
    try {
      final result = await _channel.invokeMethod<bool>('sendTestNotification');
      return Success(result);
    } catch (error) {
      return FailureResult(UnknownFailure('Could not send test notification: $error'));
    }
  }

  @override
  Future<Result<String?>> getDeviceId() async {
    try {
      final result = await _channel.invokeMethod<String>('deviceId');
      return Success(result);
    } catch (error) {
      return FailureResult(UnknownFailure('Could not get device ID: $error'));
    }
  }

  @override
  Future<Result<void>> clear() async {
    try {
      await _channel.invokeMethod<void>('clear');
      return const Success(null);
    } catch (error) {
      return FailureResult(UnknownFailure('Could not clear capture config: $error'));
    }
  }

  @override
  Future<Result<void>> configure({
    required String apiUrl,
    required String deviceToken,
    required String deviceId,
  }) async {
    try {
      await _channel.invokeMethod<void>('configure', {
        'apiUrl': apiUrl,
        'deviceToken': deviceToken,
        'deviceId': deviceId,
      });
      return const Success(null);
    } catch (error) {
      return FailureResult(UnknownFailure('Could not configure capture: $error'));
    }
  }
}