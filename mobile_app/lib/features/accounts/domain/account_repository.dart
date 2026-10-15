import 'package:cardsemble/core/core.dart';
import 'package:cardsemble/features/accounts/domain/accounts_domain.dart';

abstract class AccountRepository {
  Future<Result<List<PlaidConnection>>> loadPlaidConnections();
  Future<Result<String>> createPlaidLinkToken(String platform);
  Future<Result<void>> syncPlaidConnections();
  Future<Result<void>> exchangePlaidPublicToken({
    required String publicToken,
    required String? institutionId,
    required String? institutionName,
    required String platform,
  });
  Future<Result<void>> updateCreditCardDisplayName(String accountId, String? displayName);
  Future<Result<StatementCycleSummary>> loadStatementCycles();
}