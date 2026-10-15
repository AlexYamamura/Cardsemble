import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cardsemble/features/auth/domain/auth_domain.dart';

class AuthNotifier extends ChangeNotifier {
  AuthNotifier({
    required AuthRepository authRepository,
  }) : _authRepository = authRepository {
    _authStateSubscription = _authRepository.authStateChanges().listen((session) {
      _userSession = session;
      notifyListeners();
    });
  }

  final AuthRepository _authRepository;
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