import 'package:flutter_test/flutter_test.dart';

import 'package:cardsemble/core/core.dart';
import 'package:cardsemble/features/accounts/domain/accounts_domain.dart';
import 'package:cardsemble/features/accounts/presentation/accounts_notifier.dart';

class FakeAccountRepository implements AccountRepository {
  FakeAccountRepository({
    this.linkTokenResult,
    this.exchangeResult,
    this.connectionsResult,
    this.statementCyclesResult,
    this.syncResult,
  });

  Result<String>? linkTokenResult;
  Result<PlaidSyncOutcome>? exchangeResult;
  Result<List<PlaidConnection>>? connectionsResult;
  Result<StatementCycleSummary>? statementCyclesResult;
  Result<WalletSummary>? walletSummaryResult;
  Result<PlaidSyncOutcome>? syncResult;

  final List<String> linkTokenPlatforms = [];
  final List<Map<String, Object?>> exchanges = [];
  int connectionLoads = 0;
  int statementCycleLoads = 0;
  int walletSummaryLoads = 0;

  @override
  Future<Result<List<PlaidConnection>>> loadPlaidConnections() async {
    connectionLoads++;
    return connectionsResult ?? const Success(<PlaidConnection>[]);
  }

  @override
  Future<Result<String>> createPlaidLinkToken(String platform) async {
    linkTokenPlatforms.add(platform);
    return linkTokenResult ?? const Success('link-token-1');
  }

  @override
  Future<Result<PlaidSyncOutcome>> syncPlaidConnections() async {
    return syncResult ?? const Success(PlaidSyncOutcome());
  }

  @override
  Future<Result<PlaidSyncOutcome>> exchangePlaidPublicToken({
    required String publicToken,
    required String? institutionId,
    required String? institutionName,
    required String platform,
  }) async {
    exchanges.add({
      'publicToken': publicToken,
      'institutionId': institutionId,
      'institutionName': institutionName,
      'platform': platform,
    });
    return exchangeResult ?? const Success(PlaidSyncOutcome());
  }

  @override
  Future<Result<void>> updateCreditCardDisplayName(
    String accountId,
    String? displayName,
  ) async {
    return const Success<void>(null);
  }

  @override
  Future<Result<StatementCycleSummary>> loadStatementCycles() async {
    statementCycleLoads++;
    return statementCyclesResult ??
        const Success(
          StatementCycleSummary(
            status: 'WAITING_FOR_STATEMENTS',
            total: null,
            currency: null,
            accountCount: 0,
            accounts: [],
          ),
        );
  }

  @override
  Future<Result<WalletSummary>> loadWalletSummary() async {
    walletSummaryLoads++;
    return walletSummaryResult ??
        const Success(
          WalletSummary(
            cardCount: 0,
            currencies: [],
          ),
        );
  }
}

class FakePlaidLinkLauncher implements PlaidLinkLauncher {
  FakePlaidLinkLauncher(this.result);

  PlaidLinkResult result;
  final List<String> launchedTokens = [];

  @override
  Future<PlaidLinkResult> launch({required String linkToken}) async {
    launchedTokens.add(linkToken);
    return result;
  }
}

void main() {
  group('AccountsNotifier.linkAccount', () {
    test('runs the full link flow and reloads accounts on success', () async {
      final repository = FakeAccountRepository();
      final launcher = FakePlaidLinkLauncher(
        const PlaidLinkResult.success(
          publicToken: 'public-1',
          institutionId: 'ins_1',
          institutionName: 'Chase',
        ),
      );
      final notifier = AccountsNotifier(
        accountRepository: repository,
        linkLauncher: launcher,
      );

      final success = await notifier.linkAccount();

      expect(success, isTrue);
      expect(repository.linkTokenPlatforms, ['android']);
      expect(launcher.launchedTokens, ['link-token-1']);
      expect(repository.exchanges, hasLength(1));
      expect(repository.exchanges.first['publicToken'], 'public-1');
      expect(repository.exchanges.first['institutionId'], 'ins_1');
      expect(repository.exchanges.first['institutionName'], 'Chase');
      expect(repository.exchanges.first['platform'], 'android');
      expect(repository.connectionLoads, 1);
      expect(repository.statementCycleLoads, 1);
      expect(notifier.lastLinkedInstitutionName, 'Chase');
      expect(notifier.error, isNull);
      expect(notifier.warning, isNull);
      expect(notifier.isLinking, isFalse);
    });

    test(
      'reports a warning when the post-exchange account reload fails',
      () async {
        final repository = FakeAccountRepository(
          connectionsResult: const FailureResult<List<PlaidConnection>>(
            NetworkFailure('connections unavailable'),
          ),
        );
        final launcher = FakePlaidLinkLauncher(
          const PlaidLinkResult.success(
            publicToken: 'public-1',
            institutionId: 'ins_1',
            institutionName: 'Chase',
          ),
        );
        final notifier = AccountsNotifier(
          accountRepository: repository,
          linkLauncher: launcher,
        );

        final success = await notifier.linkAccount();

        expect(success, isTrue);
        expect(repository.exchanges, hasLength(1));
        expect(repository.connectionLoads, 1);
        expect(repository.statementCycleLoads, 1);
        expect(
          notifier.warning,
          contains('Card linked, but the account list could not be reloaded'),
        );
        expect(notifier.warning, contains('connections unavailable'));
        expect(notifier.error, isNull);
        expect(notifier.lastLinkedInstitutionName, 'Chase');
        expect(notifier.isLinking, isFalse);
      },
    );

    test(
      'reports a successful link with a re-authentication warning',
      () async {
        final repository = FakeAccountRepository(
          exchangeResult: const Success(
            PlaidSyncOutcome(
              itemErrors: [
                PlaidItemSyncError(
                  itemId: 'item-1',
                  institutionName: 'Chase',
                  errorCode: 'ITEM_LOGIN_REQUIRED',
                  message: 'This connection needs to be re-authenticated.',
                ),
              ],
            ),
          ),
        );
        final launcher = FakePlaidLinkLauncher(
          const PlaidLinkResult.success(
            publicToken: 'public-1',
            institutionId: 'ins_1',
            institutionName: 'Chase',
          ),
        );
        final notifier = AccountsNotifier(
          accountRepository: repository,
          linkLauncher: launcher,
        );

        final success = await notifier.linkAccount();

        expect(success, isTrue);
        expect(notifier.error, isNull);
        expect(
          notifier.warning,
          'Chase connected. Chase needs re-authentication.',
        );
        expect(notifier.isLinking, isFalse);
      },
    );

    test(
      'does not launch Plaid Link when the link token cannot be created',
      () async {
        final repository = FakeAccountRepository(
          linkTokenResult: const FailureResult<String>(
            NetworkFailure('no link token for you'),
          ),
        );
        final launcher = FakePlaidLinkLauncher(
          const PlaidLinkResult.success(publicToken: 'public-1'),
        );
        final notifier = AccountsNotifier(
          accountRepository: repository,
          linkLauncher: launcher,
        );

        final success = await notifier.linkAccount();

        expect(success, isFalse);
        expect(launcher.launchedTokens, isEmpty);
        expect(repository.exchanges, isEmpty);
        expect(notifier.error, 'no link token for you');
        expect(notifier.isLinking, isFalse);
      },
    );

    test('surfaces a user exit without exchanging a token', () async {
      final repository = FakeAccountRepository();
      final launcher = FakePlaidLinkLauncher(
        const PlaidLinkResult.exited(message: 'Card linking was cancelled.'),
      );
      final notifier = AccountsNotifier(
        accountRepository: repository,
        linkLauncher: launcher,
      );

      final success = await notifier.linkAccount();

      expect(success, isFalse);
      expect(repository.exchanges, isEmpty);
      expect(notifier.error, 'Card linking was cancelled.');
      expect(notifier.lastLinkedInstitutionName, isNull);
      expect(notifier.isLinking, isFalse);
    });

    test(
      'surfaces an exchange failure and skips the statement reload',
      () async {
        final repository = FakeAccountRepository(
          exchangeResult: const FailureResult<PlaidSyncOutcome>(
            NetworkFailure('exchange failed'),
          ),
        );
        final launcher = FakePlaidLinkLauncher(
          const PlaidLinkResult.success(
            publicToken: 'public-1',
            institutionName: 'Chase',
          ),
        );
        final notifier = AccountsNotifier(
          accountRepository: repository,
          linkLauncher: launcher,
        );

        final success = await notifier.linkAccount();

        expect(success, isFalse);
        expect(notifier.error, 'exchange failed');
        expect(notifier.warning, isNull);
        expect(notifier.lastLinkedInstitutionName, isNull);
        expect(repository.statementCycleLoads, 0);
        expect(notifier.isLinking, isFalse);
      },
    );
  });

  group('AccountsNotifier.syncConnections', () {
    test('reports a warning when an item could not be synced', () async {
      final repository = FakeAccountRepository(
        syncResult: const Success(
          PlaidSyncOutcome(
            itemErrors: [
              PlaidItemSyncError(
                itemId: 'item-1',
                institutionName: 'AAA',
                errorCode: 'ITEM_LOGIN_REQUIRED',
                message: 'This connection needs to be re-authenticated.',
              ),
            ],
          ),
        ),
      );
      final notifier = AccountsNotifier(
        accountRepository: repository,
        linkLauncher: FakePlaidLinkLauncher(
          const PlaidLinkResult.success(publicToken: 'public-1'),
        ),
      );

      final success = await notifier.syncConnections();

      expect(success, isTrue);
      expect(notifier.error, isNull);
      expect(
        notifier.warning,
        'Sync finished with warnings: AAA needs re-authentication.',
      );
    });

    test('does not warn when every item synced cleanly', () async {
      final repository = FakeAccountRepository();
      final notifier = AccountsNotifier(
        accountRepository: repository,
        linkLauncher: FakePlaidLinkLauncher(
          const PlaidLinkResult.success(publicToken: 'public-1'),
        ),
      );

      final success = await notifier.syncConnections();

      expect(success, isTrue);
      expect(notifier.error, isNull);
      expect(notifier.warning, isNull);
    });
  });
}
