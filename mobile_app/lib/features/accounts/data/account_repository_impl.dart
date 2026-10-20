import 'package:supabase_flutter/supabase_flutter.dart' hide AuthException;
import 'package:cardsemble/core/core.dart';
import 'package:cardsemble/features/accounts/domain/accounts_domain.dart';

class AccountRepositoryImpl implements AccountRepository {
  AccountRepositoryImpl({
    required SupabaseApiClient apiClient,
    required SupabaseClient supabase,
  })  : _apiClient = apiClient,
        _supabase = supabase;

  final SupabaseApiClient _apiClient;
  final SupabaseClient _supabase;

  String get _currentUserId {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw const AuthException('Your session has expired. Sign in again.');
    }
    return user.id;
  }

  @override
  Future<Result<List<PlaidConnection>>> loadPlaidConnections() async {
    try {
      final userId = _currentUserId;
      final data = await _supabase
          .from('plaid_items')
          .select('item_id,institution_id,institution_name,status,created_at')
          .eq('user_id', userId)
          .neq('status', 'disconnected')
          .order('created_at', ascending: true)
          .order('item_id', ascending: true);
      return Success(
        (data as List?)
            ?.map((row) => PlaidConnection.fromJson(row))
            .toList(growable: false) ??
            [],
      );
    } catch (error) {
      return FailureResult(DatabaseFailure('Could not load bank connections: $error'));
    }
  }

  @override
  Future<Result<String>> createPlaidLinkToken(String platform) async {
    final result = await _apiClient.safePost(
      '/api/plaid/items/link-token?platform=${Uri.encodeQueryComponent(platform)}',
      const {},
    );
    return result.map((payload) {
      final token = payload['link_token'];
      if (token is! String || token.isEmpty) {
        throw const NetworkException('The card service did not return a Plaid Link token.');
      }
      return token;
    });
  }

  @override
  Future<Result<void>> syncPlaidConnections() async {
    final result = await _apiClient.safePost('/api/plaid/items/sync', const {});
    return result.map((_) {});
  }

  @override
  Future<Result<void>> exchangePlaidPublicToken({
    required String publicToken,
    required String? institutionId,
    required String? institutionName,
    required String platform,
  }) async {
    final result = await _apiClient.safePost('/api/plaid/items/exchange', {
      'public_token': publicToken,
      'institution_id': institutionId,
      'institution_name': institutionName,
      'platform': platform,
    });
    return result.map((_) {});
  }

  @override
  Future<Result<void>> updateCreditCardDisplayName(String accountId, String? displayName) async {
    try {
      final userId = _currentUserId;
      await _supabase
          .from('plaid_credit_accounts')
          .update({'display_name': displayName})
          .eq('account_id', accountId)
          .eq('user_id', userId);
      return const Success(null);
    } catch (error) {
      return FailureResult(DatabaseFailure('Could not save the credit card name: $error'));
    }
  }

  @override
  Future<Result<StatementCycleSummary>> loadStatementCycles() async {
    final result = await _apiClient.safeGet('/api/owed/statement-cycles');
    return result.map(StatementCycleSummary.fromJson);
  }
}