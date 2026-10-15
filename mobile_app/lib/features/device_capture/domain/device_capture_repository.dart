import 'package:cardsemble/core/core.dart';
import 'package:cardsemble/features/device_capture/domain/device_capture_domain.dart';

abstract class DeviceCaptureRepository {
  Future<Result<DeviceCaptureCredentials>> createGooglePayDeviceToken(String personId);
  Future<Result<void>> revokeDeviceToken(String deviceId);
  Future<Result<bool>> isConfigured();
  Future<Result<bool>> hasNotificationAccess();
  Future<Result<void>> openNotificationAccessSettings();
  Future<Result<bool?>> sendTestNotification();
  Future<Result<String?>> getDeviceId();
  Future<Result<void>> clear();
  Future<Result<void>> configure({
    required String apiUrl,
    required String deviceToken,
    required String deviceId,
  });
}