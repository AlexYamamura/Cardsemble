import 'package:cardsemble/core/core.dart';
import 'package:cardsemble/features/accounts/domain/accounts_domain.dart';

abstract class AccountRepository {
  Future<Result<List<PlaidConnection>>> loadPlaidConnections();
  Future<Result<String>> createPlaidLinkToken(String platform);
  Future<Result<String>> createPlaidLinkTokenForItem(String platform, String itemId);
  Future<Result<PlaidSyncOutcome>> syncPlaidConnections();
  Future<Result<PlaidSyncOutcome>> syncPlaidItem(String itemId);
  Future<Result<PlaidSyncOutcome>> exchangePlaidPublicToken({
    required String publicToken,
    required String? institutionId,
    required String? institutionName,
    required String platform,
  });
  Future<Result<void>> updateCreditCardDisplayName(String accountId, String? displayName);
  Future<Result<void>> updateCreditCardConfig({
    required String accountId,
    required CardType cardType,
    required CardAssigneeMode defaultAssigneeMode,
    String? defaultAssigneePersonId,
  });
  Future<Result<StatementCycleSummary>> loadStatementCycles();
  Future<Result<WalletSummary>> loadWalletSummary();
}