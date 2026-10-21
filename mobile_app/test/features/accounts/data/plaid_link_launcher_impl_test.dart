import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:plaid_flutter/plaid_flutter.dart';

import 'package:cardsemble/features/accounts/data/plaid_link_launcher_impl.dart';
import 'package:cardsemble/features/accounts/domain/accounts_domain.dart';

class FakePlaidPlatform extends PlaidPlatformInterface {
  FakePlaidPlatform();

  final StreamController<LinkObject> controller =
      StreamController<LinkObject>.broadcast();

  int createCalls = 0;
  int openCalls = 0;
  Object? createError;

  @override
  Stream<LinkObject> get onObject => controller.stream;

  @override
  Future<void> create({required LinkTokenConfiguration configuration}) async {
    createCalls++;
    if (createError != null) {
      throw createError!;
    }
  }

  @override
  Future<void> open() async {
    openCalls++;
  }
}

LinkSuccess _success({String? institutionId, String? institutionName}) {
  return LinkSuccess(
    publicToken: 'public-1',
    metadata: LinkSuccessMetadata(
      linkSessionId: 'session-1',
      institution: (institutionId == null && institutionName == null)
          ? null
          : LinkInstitution(
              id: institutionId ?? '',
              name: institutionName ?? '',
            ),
      accounts: const [],
    ),
  );
}

LinkExit _exit({LinkError? error, String? institutionName}) {
  return LinkExit(
    error: error,
    metadata: LinkExitMetadata(
      status: 'requiresCredentials',
      requestId: 'request-1',
      linkSessionId: 'session-1',
      institution: institutionName == null
          ? null
          : LinkInstitution(id: 'ins_1', name: institutionName),
    ),
  );
}

void main() {
  late PlaidPlatformInterface original;

  setUp(() {
    original = PlaidPlatformInterface.instance;
  });

  tearDown(() {
    PlaidPlatformInterface.instance = original;
  });

  test('maps a Link success event to a successful result', () async {
    final platform = FakePlaidPlatform();
    PlaidPlatformInterface.instance = platform;
    addTearDown(platform.controller.close);

    final launcher = PlaidLinkLauncherImpl();
    final future = launcher.launch(linkToken: 'link-token-1');
    await Future<void>.delayed(Duration.zero);

    platform.controller.add(
      _success(institutionId: 'ins_1', institutionName: 'Chase'),
    );

    final result = await future;

    expect(result.isSuccess, isTrue);
    expect(result.status, PlaidLinkStatus.success);
    expect(result.publicToken, 'public-1');
    expect(result.institutionId, 'ins_1');
    expect(result.institutionName, 'Chase');
    expect(platform.createCalls, 1);
    expect(platform.openCalls, 1);
  });

  test('maps a Link exit event to an exited result', () async {
    final platform = FakePlaidPlatform();
    PlaidPlatformInterface.instance = platform;
    addTearDown(platform.controller.close);

    final launcher = PlaidLinkLauncherImpl();
    final future = launcher.launch(linkToken: 'link-token-1');
    await Future<void>.delayed(Duration.zero);

    platform.controller.add(
      _exit(
        error: LinkError(
          code: 'INVALID_CREDENTIALS',
          type: 'ITEM_ERROR',
          message: 'the credentials were invalid',
          displayMessage: 'The credentials you entered are not correct.',
        ),
      ),
    );

    final result = await future;

    expect(result.isSuccess, isFalse);
    expect(result.status, PlaidLinkStatus.exited);
    expect(result.message, 'The credentials you entered are not correct.');
    expect(result.publicToken, isNull);
  });

  test('maps a platform failure to a failed result', () async {
    final platform = FakePlaidPlatform()..createError = Exception('boom');
    PlaidPlatformInterface.instance = platform;
    addTearDown(platform.controller.close);

    final launcher = PlaidLinkLauncherImpl();
    final result = await launcher.launch(linkToken: 'link-token-1');

    expect(result.isSuccess, isFalse);
    expect(result.status, PlaidLinkStatus.failed);
    expect(result.message, contains('Could not open Plaid Link'));
  });
}
