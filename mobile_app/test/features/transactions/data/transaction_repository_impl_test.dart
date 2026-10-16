import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:cardsemble/core/core.dart';
import 'package:cardsemble/features/transactions/data/transaction_repository_impl.dart';
import 'package:cardsemble/features/transactions/domain/transactions_domain.dart';

TransactionRepositoryImpl buildRepository(MockClient client) {
  return TransactionRepositoryImpl(
    apiClient: ApiClient(
      baseUrl: 'https://example.test',
      accessTokenProvider: () => 'token',
      client: client,
    ),
  );
}

void main() {
  group('loadTransactions', () {
    test('surfaces a failed page as a failure instead of partial data', () async {
      final client = MockClient(
        (request) async => http.Response('{"detail":"boom"}', 500),
      );
      final repository = buildRepository(client);

      final result = await repository.loadTransactions(const TransactionQuery());

      expect(result.isFailure, isTrue);
    });

    test('parses a page and reports has_more and household visibility', () async {
      final client = MockClient((request) async {
        expect(request.url.queryParameters['limit'], '100');
        expect(request.url.queryParameters['account_id'], 'a1');
        return http.Response(
          jsonEncode({
            'transactions': [
              {
                'transaction_id': 't1',
                'account_id': 'a1',
                'amount': -12.5,
                'iso_currency_code': 'USD',
                'date': '2026-01-02',
                'name': 'Coffee',
                'pending': false,
                'transaction_code': 'purchase',
                'assigned_person_id': 'p1',
                'assignment_source': 'manual',
                'has_splits': false,
                'household_visible': false,
              }
            ],
            'has_more': true,
          }),
          200,
        );
      });
      final repository = buildRepository(client);

      final result = await repository.loadTransactions(
        const TransactionQuery(accountId: 'a1'),
      );

      expect(result.isSuccess, isTrue);
      final page = result.value;
      expect(page.hasMore, isTrue);
      expect(page.items, hasLength(1));
      expect(page.items.first.id, 't1');
      expect(page.items.first.householdVisible, isFalse);
    });

    test('surfaces a malformed row as a failure', () async {
      final client = MockClient(
        (request) async => http.Response(
          jsonEncode({
            'transactions': [
              {'account_id': 'a1'}
            ],
            'has_more': false,
          }),
          200,
        ),
      );
      final repository = buildRepository(client);

      final result = await repository.loadTransactions(const TransactionQuery());

      expect(result.isFailure, isTrue);
    });
  });

  group('assignTransaction', () {
    test('resolves the household default person when unassigning', () async {
      final client = MockClient(
        (request) async => http.Response(
          jsonEncode({
            'ok': true,
            'transaction_id': 't1',
            'person_id': 'default-person',
            'assignment_source': 'default',
          }),
          200,
        ),
      );
      final repository = buildRepository(client);

      final result = await repository.assignTransaction('t1', null);

      expect(result.isSuccess, isTrue);
      expect(result.value.personId, 'default-person');
      expect(result.value.assignmentSource, 'default');
    });

    test('reads the nested assignment when assigning a person', () async {
      final client = MockClient(
        (request) async => http.Response(
          jsonEncode({
            'ok': true,
            'assignment': {'person_id': 'p2', 'assignment_source': 'manual'},
          }),
          200,
        ),
      );
      final repository = buildRepository(client);

      final result = await repository.assignTransaction('t1', 'p2');

      expect(result.isSuccess, isTrue);
      expect(result.value.personId, 'p2');
      expect(result.value.assignmentSource, 'manual');
    });
  });
}
