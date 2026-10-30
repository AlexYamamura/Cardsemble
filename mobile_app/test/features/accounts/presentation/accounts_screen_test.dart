import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:cardsemble/core/core.dart';
import 'package:cardsemble/features/accounts/domain/accounts_domain.dart';
import 'package:cardsemble/features/accounts/presentation/accounts_notifier.dart';
import 'package:cardsemble/features/accounts/presentation/accounts_screen.dart';

class _FakeAccountRepository implements AccountRepository {
  _FakeAccountRepository({this.exchangeResult, this.connectionsResult});

  final Result<PlaidSyncOutcome>? exchangeResult;
  final Result<List<PlaidConnection>>? connectionsResult;
  int exchangeCalls = 0;

  @override
  Future<Result<List<PlaidConnection>>> loadPlaidConnections() async {
    return connectionsResult ?? const Success(<PlaidConnection>[]);
  }

  @override
  Future<Result<String>> createPlaidLinkToken(String platform) async {
    return const Success('link-token-1');
  }

  @override
  Future<Result<String>> createPlaidLinkTokenForItem(String platform, String itemId) async {
    return const Success('link-token-1');
  }

  @override
  Future<Result<PlaidSyncOutcome>> syncPlaidConnections() async {
    return const Success(PlaidSyncOutcome());
  }

  @override
  Future<Result<PlaidSyncOutcome>> syncPlaidItem(String itemId) async {
    return const Success(PlaidSyncOutcome());
  }

  @override
  Future<Result<PlaidSyncOutcome>> exchangePlaidPublicToken({
    required String publicToken,
    required String? institutionId,
    required String? institutionName,
    required String platform,
  }) async {
    exchangeCalls++;
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
  Future<Result<void>> updateCreditCardConfig({
    required String accountId,
    required CardType cardType,
    required CardAssigneeMode defaultAssigneeMode,
    String? defaultAssigneePersonId,
  }) async {
    return const Success<void>(null);
  }

  @override
  Future<Result<StatementCycleSummary>> loadStatementCycles() async {
    return const Success(
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
    return const Success(
      WalletSummary(
        cardCount: 0,
        currencies: [],
      ),
    );
  }
}

class _FakePlaidLinkLauncher implements PlaidLinkLauncher {
  _FakePlaidLinkLauncher(this.result);

  final PlaidLinkResult result;

  @override
  Future<PlaidLinkResult> launch({required String linkToken}) async {
    return result;
  }
}

Widget _wrap(AccountsNotifier notifier) {
  return ChangeNotifierProvider<AccountsNotifier>.value(
    value: notifier,
    child: const MaterialApp(home: AccountsScreen()),
  );
}

void main() {
  testWidgets('shows a success snackbar after linking a card', (tester) async {
    final notifier = AccountsNotifier(
      accountRepository: _FakeAccountRepository(),
      linkLauncher: _FakePlaidLinkLauncher(
        const PlaidLinkResult.success(
          publicToken: 'public-1',
          institutionName: 'Chase',
        ),
      ),
    );

    await tester.pumpWidget(_wrap(notifier));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Link Account'));
    await tester.pumpAndSettle();

    expect(find.text('Chase connected.'), findsOneWidget);
    expect(find.text('Card linked successfully.'), findsNothing);
  });

  testWidgets('shows the error message when the exchange fails', (
    tester,
  ) async {
    final notifier = AccountsNotifier(
      accountRepository: _FakeAccountRepository(
        exchangeResult: const FailureResult<PlaidSyncOutcome>(
          NetworkFailure('exchange failed'),
        ),
      ),
      linkLauncher: _FakePlaidLinkLauncher(
        const PlaidLinkResult.success(
          publicToken: 'public-1',
          institutionName: 'Chase',
        ),
      ),
    );

    await tester.pumpWidget(_wrap(notifier));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Link Account'));
    await tester.pumpAndSettle();

    expect(find.text('exchange failed'), findsOneWidget);
    expect(find.text('Chase connected.'), findsNothing);
    expect(find.text('Card linked successfully.'), findsNothing);
  });

  testWidgets('shows the reload warning after a successful link', (
    tester,
  ) async {
    final notifier = AccountsNotifier(
      accountRepository: _FakeAccountRepository(
        connectionsResult: const FailureResult<List<PlaidConnection>>(
          NetworkFailure('connections unavailable'),
        ),
      ),
      linkLauncher: _FakePlaidLinkLauncher(
        const PlaidLinkResult.success(
          publicToken: 'public-1',
          institutionName: 'Chase',
        ),
      ),
    );

    await tester.pumpWidget(_wrap(notifier));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Link Account'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining(
        'Card linked, but the account list could not be reloaded',
      ),
      findsOneWidget,
    );
    expect(find.text('Chase connected.'), findsNothing);
    expect(find.text('Card linked successfully.'), findsNothing);
  });

  testWidgets('shows a re-authentication warning after a successful link', (
    tester,
  ) async {
    final notifier = AccountsNotifier(
      accountRepository: _FakeAccountRepository(
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
      ),
      linkLauncher: _FakePlaidLinkLauncher(
        const PlaidLinkResult.success(
          publicToken: 'public-1',
          institutionName: 'Chase',
        ),
      ),
    );

    await tester.pumpWidget(_wrap(notifier));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Link Account'));
    await tester.pumpAndSettle();

    expect(
      find.text('Chase connected. Chase needs re-authentication.'),
      findsOneWidget,
    );
    expect(find.text('Could not link a card.'), findsNothing);
  });
}
