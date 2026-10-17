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

  group('fetchTransactionSplits', () {
    test('returns success with two valid splits', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/plaid-transactions/t1/splits');
        return http.Response(
          jsonEncode({
            'splits': [
              {'person_id': 'p1', 'amount': 5.25},
              {'person_id': 'p2', 'amount': 4.75},
            ],
          }),
          200,
        );
      });
      final repository = buildRepository(client);
      final result = await repository.fetchTransactionSplits('t1');
      expect(result.isSuccess, isTrue);
      final splits = result.value;
      expect(splits, hasLength(2));
      expect(splits[0].personId, 'p1');
      expect(splits[0].amount, 5.25);
      expect(splits[1].personId, 'p2');
      expect(splits[1].amount, 4.75);
    });

    test('skips null amount rows (single assignment)', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/plaid-transactions/t1/splits');
        return http.Response(
          jsonEncode({
            'splits': [
              {'person_id': 'p1', 'amount': null},
              {'person_id': 'p2', 'amount': 10.0},
            ],
          }),
          200,
        );
      });
      final repository = buildRepository(client);
      final result = await repository.fetchTransactionSplits('t1');
      expect(result.isSuccess, isTrue);
      final splits = result.value;
      expect(splits, hasLength(1));
      expect(splits[0].personId, 'p2');
      expect(splits[0].amount, 10.0);
    });

    test('skips zero and negative amounts', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/plaid-transactions/t1/splits');
        return http.Response(
          jsonEncode({
            'splits': [
              {'person_id': 'p1', 'amount': 0},
              {'person_id': 'p2', 'amount': -5.0},
              {'person_id': 'p3', 'amount': 7.5},
            ],
          }),
          200,
        );
      });
      final repository = buildRepository(client);
      final result = await repository.fetchTransactionSplits('t1');
      expect(result.isSuccess, isTrue);
      final splits = result.value;
      expect(splits, hasLength(1));
      expect(splits[0].personId, 'p3');
      expect(splits[0].amount, 7.5);
    });

    test('skips empty or non-string personId', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/plaid-transactions/t1/splits');
        return http.Response(
          jsonEncode({
            'splits': [
              {'person_id': '', 'amount': 5.0},
              {'person_id': null, 'amount': 5.0},
              {'person_id': 'p1', 'amount': 5.0},
            ],
          }),
          200,
        );
      });
      final repository = buildRepository(client);
      final result = await repository.fetchTransactionSplits('t1');
      expect(result.isSuccess, isTrue);
      final splits = result.value;
      expect(splits, hasLength(1));
      expect(splits[0].personId, 'p1');
      expect(splits[0].amount, 5.0);
    });

    test('accepts numeric string amounts', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/plaid-transactions/t1/splits');
        return http.Response(
          jsonEncode({
            'splits': [
              {'person_id': 'p1', 'amount': '5.25'},
              {'person_id': 'p2', 'amount': '4.75'},
            ],
          }),
          200,
        );
      });
      final repository = buildRepository(client);
      final result = await repository.fetchTransactionSplits('t1');
      expect(result.isSuccess, isTrue);
      final splits = result.value;
      expect(splits, hasLength(2));
      expect(splits[0].amount, 5.25);
      expect(splits[1].amount, 4.75);
    });

    test('returns empty list when splits key is missing', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/plaid-transactions/t1/splits');
        return http.Response(
          jsonEncode({
            // no splits key
          }),
          200,
        );
      });
      final repository = buildRepository(client);
      final result = await repository.fetchTransactionSplits('t1');
      expect(result.isSuccess, isTrue);
      final splits = result.value;
      expect(splits, isEmpty);
    });

    test('returns failure when splits is not a list', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/plaid-transactions/t1/splits');
        return http.Response(
          jsonEncode({
            'splits': 'not a list',
          }),
          200,
        );
      });
      final repository = buildRepository(client);
      final result = await repository.fetchTransactionSplits('t1');
      expect(result.isFailure, isTrue);
      expect(result.failure, isA<UnknownFailure>());
    });

    test('propagates HTTP error as failure', () async {
      final client = MockClient((request) async => http.Response('{"detail":"boom"}', 500));
      final repository = buildRepository(client);
      final result = await repository.fetchTransactionSplits('t1');
      expect(result.isFailure, isTrue);
      expect(result.failure, isA<NetworkFailure>());
    });
  });
}
