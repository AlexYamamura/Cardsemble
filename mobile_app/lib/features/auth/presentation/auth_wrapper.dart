import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cardsemble/features/accounts/presentation/accounts_notifier.dart';
import 'package:cardsemble/features/auth/presentation/auth_notifier.dart';
import 'package:cardsemble/features/auth/presentation/sign_in_screen.dart';
import 'package:cardsemble/features/card_events/presentation/card_events_notifier.dart';
import 'package:cardsemble/features/device_capture/presentation/device_capture_notifier.dart';
import 'package:cardsemble/features/household/presentation/household_notifier.dart';
import 'package:cardsemble/features/transactions/presentation/transactions_notifier.dart';

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  late final AuthNotifier _authNotifier;
  String? _lastUserId;

  @override
  void initState() {
    super.initState();
    _authNotifier = context.read<AuthNotifier>();
    _lastUserId = _authNotifier.userSession?.userId;
    _authNotifier.addListener(_onAuthStateChanged);
    // Initialize after the current frame to avoid calling notifyListeners during build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _authNotifier.initialize();
      }
    });
  }

  @override
  void dispose() {
    _authNotifier.removeListener(_onAuthStateChanged);
    super.dispose();
  }

  void _onAuthStateChanged() {
    if (!mounted) return;

    final nextUserId = _authNotifier.userSession?.userId;
    if (_lastUserId != nextUserId) {
      _lastUserId = nextUserId;
      _resetSessionScopedState();
    }
    setState(() {});
  }

  /// Clears in-memory state that belongs to the previous identity.
  ///
  /// Disk caches are already keyed by user id and the sign-out path clears the
  /// session's snapshot. This prevents the new session from rendering old rows
  /// during the first frame before its own loads complete.
  void _resetSessionScopedState() {
    context.read<TransactionsNotifier>().resetForSessionChange();
    context.read<HouseholdNotifier>().reset();
    context.read<AccountsNotifier>().reset();
    context.read<CardEventsNotifier>().reset();
    context.read<DeviceCaptureNotifier>().resetSessionData();
  }

  @override
  Widget build(BuildContext context) {
    if (_authNotifier.isLoading) {
      return const _AuthLoadingScreen();
    }

    if (!_authNotifier.isAuthenticated) {
      return const SignInScreen();
    }

    return widget.child;
  }
}

class _AuthLoadingScreen extends StatelessWidget {
  const _AuthLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            const Text('Restoring session...'),
          ],
        ),
      ),
    );
  }
}
