import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cardsemble/features/device_capture/domain/device_capture_domain.dart';
import 'package:cardsemble/features/household/domain/household_domain.dart';

class DeviceCaptureNotifier extends ChangeNotifier {
  DeviceCaptureNotifier({
    required DeviceCaptureRepository deviceCaptureRepository,
    required HouseholdRepository householdRepository,
  }) : _deviceCaptureRepository = deviceCaptureRepository,
       _householdRepository = householdRepository;

  final DeviceCaptureRepository _deviceCaptureRepository;
  final HouseholdRepository _householdRepository;

  List<HouseholdPerson> _people = [];
  bool _isLoading = false;
  String? _error;
  DeviceCaptureCredentials? _credentials;
  bool _isConfigured = false;
  bool _hasNotificationAccess = false;
  String? _deviceId;
  bool _step1AutoConfigured = false;

  List<HouseholdPerson> get people => _people;
  bool get isLoading => _isLoading;
  String? get error => _error;
  DeviceCaptureCredentials? get credentials => _credentials;
  bool get isConfigured => _isConfigured;
  bool get hasNotificationAccess => _hasNotificationAccess;
  String? get deviceId => _deviceId;
  bool get step1AutoConfigured => _step1AutoConfigured;

  void setStep1AutoConfigured(bool value) {
    _step1AutoConfigured = value;
    notifyListeners();
  }

  Future<void> loadPeople() async {
    try {
      final result = await _householdRepository.loadPeople();
      result.fold(
        (people) => _people = people,
        (failure) => _error = failure.message,
      );
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> checkStatus() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final configuredResult = await _deviceCaptureRepository.isConfigured();
      configuredResult.fold(
        (configured) => _isConfigured = configured,
        (failure) => _error = failure.message,
      );

      final accessResult = await _deviceCaptureRepository.hasNotificationAccess();
      accessResult.fold(
        (access) => _hasNotificationAccess = access,
        (failure) => _error = failure.message,
      );

      final deviceIdResult = await _deviceCaptureRepository.getDeviceId();
      deviceIdResult.fold(
        (id) => _deviceId = id,
        (failure) => _error = failure.message,
      );
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> createDeviceToken(String personId) async {
    _error = null;
    _credentials = null;
    notifyListeners();

    try {
      final result = await _deviceCaptureRepository.createGooglePayDeviceToken(personId);
      return result.fold(
        (credentials) {
          _credentials = credentials;
          notifyListeners();
          return true;
        },
        (failure) {
          _error = failure.message;
          notifyListeners();
          return false;
        },
      );
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> configureCapture(String apiUrl) async {
    if (_credentials == null) return false;
    _deviceId ??= _generateDeviceId();

    _error = null;
    notifyListeners();

    try {
      final result = await _deviceCaptureRepository.configure(
        apiUrl: apiUrl,
        deviceToken: _credentials!.token,
        deviceId: _deviceId!,
      );
      return result.fold(
        (_) {
          _isConfigured = true;
          notifyListeners();
          return true;
        },
        (failure) {
          _error = failure.message;
          notifyListeners();
          return false;
        },
      );
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> sendTestNotification() async {
    _error = null;
    notifyListeners();

    try {
      final result = await _deviceCaptureRepository.sendTestNotification();
      return result.fold(
        (sent) {
          if (sent == true) {
            _hasNotificationAccess = true;
          }
          notifyListeners();
          return sent ?? false;
        },
        (failure) {
          _error = failure.message;
          notifyListeners();
          return false;
        },
      );
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<void> openNotificationAccessSettings() async {
    try {
      await _deviceCaptureRepository.openNotificationAccessSettings();
      checkStatus();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<bool> revokeDeviceToken(String deviceId) async {
    _error = null;
    notifyListeners();

    try {
      final result = await _deviceCaptureRepository.revokeDeviceToken(deviceId);
      return result.fold(
        (_) {
          checkStatus();
          return true;
        },
        (failure) {
          _error = failure.message;
          notifyListeners();
          return false;
        },
      );
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> clearCapture() async {
    _error = null;
    notifyListeners();

    try {
      final result = await _deviceCaptureRepository.clear();
      return result.fold(
        (_) {
          _isConfigured = false;
          _credentials = null;
          notifyListeners();
          return true;
        },
        (failure) {
          _error = failure.message;
          notifyListeners();
          return false;
        },
      );
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  String _generateDeviceId() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random.secure();
    return List.generate(32, (_) => chars[random.nextInt(chars.length)]).join();
  }
}