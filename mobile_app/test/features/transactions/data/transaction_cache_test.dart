import 'package:flutter_test/flutter_test.dart';

import 'package:cardsemble/core/cache/cache.dart';
import 'package:cardsemble/features/accounts/domain/accounts_domain.dart';
import 'package:cardsemble/features/household/domain/household_domain.dart';
import 'package:cardsemble/features/transactions/data/transaction_cache.dart';
import 'package:cardsemble/features/transactions/domain/transactions_domain.dart';

import '../../../core/cache/fake_cache_store.dart';

HouseholdPerson _person(String id) =>
    HouseholdPerson(id: id, displayName: id, isDefault: id == 'p1');

StatementAccount _account(String id) =>
    StatementAccount(accountId: id, accountName: id);

CardTransaction _tx(String id) => CardTransaction(
      id: id,
      accountId: 'a1',
      amount: '-10',
      currency: 'USD',
      date: '2026-01-02',
      name: 'Coffee',
      pending: false,
      assignmentSource: 'default',
    );

void main() {
  late FakeCacheStore store;
  late DateTime now;
  late String? scope;
  late DateTime t0;

  TransactionCache cache({Duration ttl = kDefaultCacheTtl}) {
    return TransactionCache(
      store: store,
      clock: () => now,
      scopeProvider: () => scope,
      ttl: ttl,
    );
  }

  setUp(() {
    store = FakeCacheStore();
    now = DateTime(2026, 1, 1, 12);
    t0 = now;
    scope = 'user-a';
  });

  test('writes and reads all four sections', () async {
    final sut = cache();

    final written = await sut.write(
      scope: scope,
      people: [_person('p1')],
      accounts: [_account('a1')],
      transactions: [_tx('t1')],
      summaryTransactions: [_tx('t2')],
    );

    expect(written, isTrue);
    final snapshot = await sut.read();

    expect(snapshot.people.items.single.id, 'p1');
    expect(snapshot.accounts.items.single.accountId, 'a1');
    expect(snapshot.transactions.items.single.id, 't1');
    expect(snapshot.summaryTransactions.items.single.id, 't2');
    expect(snapshot.people.savedAt!.isAtSameMomentAs(t0), isTrue);
    expect(snapshot.transactions.savedAt!.isAtSameMomentAs(t0), isTrue);
  });

  test('a partial write updates only the supplied section timestamp', () async {
    final sut = cache();
    await sut.write(scope: scope, people: [_person('p1')]);

    now = now.add(const Duration(minutes: 5));
    final secondWriteAt = now;
    await sut.write(scope: scope, accounts: [_account('a1')]);

    final snapshot = await sut.read();

    expect(snapshot.people.savedAt!.isAtSameMomentAs(t0), isTrue);
    expect(snapshot.accounts.savedAt!.isAtSameMomentAs(secondWriteAt), isTrue);
    expect(snapshot.transactions.savedAt, isNull);
  });

  test('section freshness honors the TTL', () async {
    final sut = cache();
    await sut.write(scope: scope, people: [_person('p1')]);
    final snapshot = await sut.read();

    expect(
      snapshot.people.isFresh(now.add(const Duration(hours: 23)), kDefaultCacheTtl),
      isTrue,
    );
    expect(
      snapshot.people.isFresh(now.add(const Duration(hours: 25)), kDefaultCacheTtl),
      isFalse,
    );
  });

  test('one corrupt section does not discard the other sections', () async {
    final sut = cache();
    await sut.write(
      scope: scope,
      people: [_person('p1')],
      transactions: [_tx('t1')],
    );
    final key = store.entries.keys.single;
    final record = store.entries[key]!;
    final value = Map<String, dynamic>.from(record.value! as Map);
    final sections = Map<String, dynamic>.from(value['sections'] as Map);
    sections['people'] = 'not-a-section';
    value['sections'] = sections;
    store.entries[key] = CacheRecord<Object?>(
      value: value,
      savedAt: record.savedAt,
      scope: scope!,
    );

    final snapshot = await sut.read();

    expect(snapshot.people.items, isEmpty);
    expect(snapshot.people.savedAt, isNull);
    expect(snapshot.transactions.items.single.id, 't1');
  });

  test('one malformed item invalidates its whole section', () async {
    final sut = cache();
    await sut.write(
      scope: scope,
      transactions: [_tx('t1')],
      accounts: [_account('a1')],
    );
    final key = store.entries.keys.single;
    final record = store.entries[key]!;
    final value = Map<String, dynamic>.from(record.value! as Map);
    final sections = Map<String, dynamic>.from(value['sections'] as Map);
    final transactions =
        Map<String, dynamic>.from(sections['transactions'] as Map);
    transactions['items'] = <Object>[42];
    sections['transactions'] = transactions;
    value['sections'] = sections;
    store.entries[key] = CacheRecord<Object?>(
      value: value,
      savedAt: record.savedAt,
      scope: scope!,
    );

    final snapshot = await sut.read();

    expect(snapshot.transactions.items, isEmpty);
    expect(snapshot.transactions.savedAt, isNull);
    expect(snapshot.accounts.items.single.accountId, 'a1');
  });

  test('one snapshot key is used per scope', () async {
    final sut = cache();
    scope = 'user-a';
    await sut.write(scope: 'user-a', people: [_person('p1')]);
    scope = 'user-b';
    await sut.write(scope: 'user-b', people: [_person('p2')]);

    expect(store.entries.length, 2);
  });

  test('concurrent writes merge without losing a section', () async {
    final sut = cache();

    final peopleWrite = sut.write(scope: scope, people: [_person('p1')]);
    final accountsWrite = sut.write(scope: scope, accounts: [_account('a1')]);
    final results = await Future.wait([peopleWrite, accountsWrite]);

    expect(results, everyElement(isTrue));
    final snapshot = await sut.read();
    expect(snapshot.people.items.single.id, 'p1');
    expect(snapshot.accounts.items.single.accountId, 'a1');
  });

  test('clearing one scope leaves other identities intact', () async {
    final sut = cache();
    scope = 'user-a';
    await sut.write(scope: 'user-a', people: [_person('p1')]);
    scope = 'user-b';
    await sut.write(scope: 'user-b', people: [_person('p2')]);

    expect(await sut.clearScope('user-a'), isTrue);

    scope = 'user-a';
    expect((await sut.read()).people.items, isEmpty);
    scope = 'user-b';
    expect((await sut.read()).people.items.single.id, 'p2');
  });

  test('a write with a stale scope is rejected', () async {
    final sut = cache();

    final written = await sut.write(
      scope: 'user-b',
      people: [_person('p1')],
    );

    expect(written, isFalse);
    expect(store.entries, isEmpty);
  });

  test('legacy unscoped keys are purged', () async {
    for (final key in TransactionCache.legacyKeys) {
      store.entries[key] = CacheRecord<Object?>(
        value: 'old',
        savedAt: now,
        scope: 'legacy',
      );
    }
    store.entries['unrelated'] = CacheRecord<Object?>(
      value: 'keep',
      savedAt: now,
      scope: 'legacy',
    );
    final sut = cache();

    await sut.purgeLegacyKeys();

    expect(store.entries.keys, ['unrelated']);
  });

  test('an unsupported snapshot schema is discarded', () async {
    final sut = cache();
    await sut.write(scope: scope, people: [_person('p1')]);
    final key = store.entries.keys.single;
    await store.write(
      key,
      <String, dynamic>{'schema_version': 99, 'sections': <String, dynamic>{}},
      scope: scope!,
    );

    final snapshot = await sut.read();

    expect(snapshot.people.items, isEmpty);
    expect(store.entries, isEmpty);
  });

  test('a failed write returns false and keeps the previous snapshot', () async {
    final sut = cache();
    await sut.write(scope: scope, people: [_person('p1')]);

    store.failWrites = true;
    final written = await sut.write(scope: scope, accounts: [_account('a1')]);

    expect(written, isFalse);
    final snapshot = await sut.read();
    expect(snapshot.people.items.single.id, 'p1');
    expect(snapshot.accounts.items, isEmpty);
  });
}
