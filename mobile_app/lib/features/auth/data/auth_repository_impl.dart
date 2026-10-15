import 'package:supabase_flutter/supabase_flutter.dart' hide AuthException;
import 'package:cardsemble/core/core.dart';
import 'package:cardsemble/features/auth/domain/auth_domain.dart';

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl({
    required SupabaseClient supabase,
  }) : _supabase = supabase;

  final SupabaseClient _supabase;

  @override
  Future<Result<UserSession>> getCurrentSession() async {
    try {
      final session = _supabase.auth.currentSession;
      if (session == null) {
        return const FailureResult(AuthFailure('No active session'));
      }
      final expiresAt = session.expiresAt;
      if (expiresAt == null) {
        return const FailureResult(AuthFailure('Session missing expiration'));
      }
      return Success(UserSession(
        userId: session.user.id,
        accessToken: session.accessToken,
        expiresAt: DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000),
      ));
    } catch (e) {
      return FailureResult(AuthFailure(e.toString()));
    }
  }

  @override
  Future<Result<void>> signInWithGoogle({required String redirectUrl}) async {
    try {
      await _supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: redirectUrl,
      );
      return const Success(null);
    } catch (e) {
      return FailureResult(AuthFailure(e.toString()));
    }
  }

  @override
  Future<Result<void>> signOut() async {
    try {
      await _supabase.auth.signOut();
      return const Success(null);
    } catch (e) {
      return FailureResult(AuthFailure(e.toString()));
    }
  }

  @override
  Stream<UserSession?> authStateChanges() {
    return _supabase.auth.onAuthStateChange.asyncMap((change) async {
      final session = change.session;
      if (session == null) return null;
      final expiresAt = session.expiresAt;
      if (expiresAt == null) return null;
      return UserSession(
        userId: session.user.id,
        accessToken: session.accessToken,
        expiresAt: DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000),
      );
    });
  }
}