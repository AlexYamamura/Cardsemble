import 'package:cardsemble/core/core.dart';
import 'package:cardsemble/features/auth/domain/auth_domain.dart';

abstract class AuthRepository {
  Future<Result<UserSession>> getCurrentSession();
  Future<Result<void>> signInWithGoogle({required String redirectUrl});
  Future<Result<void>> signOut();
  Stream<UserSession?> authStateChanges();
}