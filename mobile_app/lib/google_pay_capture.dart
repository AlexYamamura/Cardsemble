import 'package:flutter/services.dart';

class GooglePayCapture {
  static const _channel = MethodChannel(
    'com.plaidtest.cardsemble/google_pay_capture',
  );

  Future<void> configure({
    required String apiUrl,
    required String deviceToken,
    required String deviceId,
  }) async {
    await _channel.invokeMethod<void>('configure', {
      'apiUrl': apiUrl,
      'deviceToken': deviceToken,
      'deviceId': deviceId,
    });
  }

  Future<void> clear() async {
    await _channel.invokeMethod<void>('clear');
  }

  Future<bool> isConfigured() async {
    return await _channel.invokeMethod<bool>('isConfigured') ?? false;
  }

  Future<String?> deviceId() async {
    return _channel.invokeMethod<String>('deviceId');
  }

  Future<bool> hasNotificationAccess() async {
    return await _channel.invokeMethod<bool>('hasNotificationAccess') ?? false;
  }

  Future<void> openNotificationAccessSettings() async {
    await _channel.invokeMethod<void>('openNotificationAccessSettings');
  }

  Future<bool?> sendTestNotification() async {
    return await _channel.invokeMethod<bool>('sendTestNotification');
  }
}
