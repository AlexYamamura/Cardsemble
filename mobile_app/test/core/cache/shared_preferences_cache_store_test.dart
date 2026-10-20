import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cardsemble/core/core.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('writes and reads a scoped envelope', () async {
    final store = SharedPreferencesCacheStore();
    final savedAt = DateTime(2026, 2, 3, 4, 5, 6);

    expect(
      await store.write(
        'cardsemble.cache.v1.demo.user-a.key',
        {'answer': 42},
        scope: 'user-a',
        savedAt: savedAt,
      ),
      isTrue,
    );

    final record = await store.read(
      'cardsemble.cache.v1.demo.user-a.key',
      scope: 'user-a',
    );

    expect(record, isNotNull);
    expect(record!.value, {'answer': 42});
    expect(record.savedAt.isAtSameMomentAs(savedAt), isTrue);
    expect(record.scope, 'user-a');
  });

  test('a foreign scope is a miss and the entry is discarded', () async {
    final store = SharedPreferencesCacheStore();
    const key = 'cardsemble.cache.v1.demo.user-a.key';
    await store.write(key, 'secret', scope: 'user-a');

    final record = await store.read(key, scope: 'user-b');
    final prefs = await SharedPreferences.getInstance();

    expect(record, isNull);
    expect(prefs.getKeys(), isEmpty);
  });

  test('corrupt JSON is a miss without crashing', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'cardsemble.cache.v1.demo.user-a.key': 'not-json',
    });
    final store = SharedPreferencesCacheStore();

    final record = await store.read(
      'cardsemble.cache.v1.demo.user-a.key',
      scope: 'user-a',
    );

    expect(record, isNull);
  });

  test('an unsupported envelope schema is discarded', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'cardsemble.cache.v1.demo.user-a.key': jsonEncode(<String, dynamic>{
        'schema_version': 999,
        'scope': 'user-a',
        'saved_at': DateTime(2026).toIso8601String(),
        'value': 'x',
      }),
    });
    final store = SharedPreferencesCacheStore();

    final record = await store.read(
      'cardsemble.cache.v1.demo.user-a.key',
      scope: 'user-a',
    );
    final prefs = await SharedPreferences.getInstance();

    expect(record, isNull);
    expect(prefs.getKeys(), isEmpty);
  });

  test('removeWhere removes only matching keys', () async {
    final store = SharedPreferencesCacheStore();
    await store.write('a', 1, scope: 'u');
    await store.write('b', 2, scope: 'u');

    expect(await store.removeWhere((key) => key == 'a'), 1);
    expect(await store.read('a', scope: 'u'), isNull);
    expect((await store.read('b', scope: 'u'))!.value, 2);
  });

  test('an encoding failure returns false instead of throwing', () async {
    final store = SharedPreferencesCacheStore();

    final written = await store.write('a', Object(), scope: 'u');

    expect(written, isFalse);
  });
}
