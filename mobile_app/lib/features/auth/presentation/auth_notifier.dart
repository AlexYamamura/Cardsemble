import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cardsemble/features/auth/domain/auth_domain.dart';

class AuthNotifier extends ChangeNotifier {
  AuthNotifier({
    required AuthRepository authRepository,
    Future<void> Function(String? previousUserId)? onBeforeSignOut,
    void Function(String previousUserId, String? nextUserId)? onUserIdChanged,
  })  : _authRepository = authRepository,
        _onBeforeSignOut = onBeforeSignOut,
        _onUserIdChanged = onUserIdChanged {
    _authStateSubscription = _authRepository.authStateChanges().listen((session) {
      final previousUserId = _userSession?.userId;
      final nextUserId = session?.userId;
      _userSession = session;
      if (previousUserId != null && previousUserId != nextUserId) {
        try {
          _onUserIdChanged?.call(previousUserId, nextUserId);
        } catch (_) {
          // Cache cleanup must never block authentication state.
        }
      }
      notifyListeners();
    });
  }

  final AuthRepository _authRepository;
  final Future<void> Function(String? previousUserId)? _onBeforeSignOut;
  final void Function(String previousUserId, String? nextUserId)? _onUserIdChanged;
  late final StreamSubscription<UserSession?> _authStateSubscription;

  UserSession? _userSession;
  bool _isLoading = true;
  String? _error;

  UserSession? get userSession => _userSession;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _userSession != null;
  String? get error => _error;

  @override
  void dispose() {
    _authStateSubscription.cancel();
    super.dispose();
  }

  Future<void> initialize() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _authRepository.getCurrentSession();
      result.fold(
        (session) => _userSession = session,
        (failure) => _error = failure.message,
      );
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> signInWithGoogle() async {
    _error = null;
    notifyListeners();

    try {
      await _authRepository.signInWithGoogle(
        redirectUrl: 'com.plaidtest.cardsemble://login-callback/',
      );
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    final previousUserId = _userSession?.userId;
    try {
      // Clear the current identity's cached data while the scope is still
      // resolvable. The scoped keys already isolate users, but erasing the
      // session snapshot avoids leaving financial data on a signed-out device.
      await _onBeforeSignOut?.call(previousUserId);
    } catch (_) {
      // Cache cleanup must not prevent sign-out.
    }

    try {
      await _authRepository.signOut();
      _userSession = null;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  void updateSession(UserSession? session) {
    _userSession = session;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}