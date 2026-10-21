import 'dart:async';

import 'package:plaid_flutter/plaid_flutter.dart';

import 'package:cardsemble/features/accounts/domain/accounts_domain.dart';

/// Launches the native Plaid Link flow and maps its callbacks to a
/// [PlaidLinkResult].
class PlaidLinkLauncherImpl implements PlaidLinkLauncher {
  static const Duration _sessionTimeout = Duration(minutes: 5);

  @override
  Future<PlaidLinkResult> launch({required String linkToken}) async {
    final completer = Completer<PlaidLinkResult>();
    StreamSubscription<LinkSuccess>? successSubscription;
    StreamSubscription<LinkExit>? exitSubscription;

    void complete(PlaidLinkResult result) {
      if (!completer.isCompleted) {
        completer.complete(result);
      }
    }

    try {
      // The static streams are derived from the platform instance, so they must
      // be subscribed to before the Link session is created.
      successSubscription = PlaidLink.onSuccess.listen((event) {
        final institution = event.metadata.institution;
        complete(
          PlaidLinkResult.success(
            publicToken: event.publicToken,
            institutionId: _normalize(institution?.id),
            institutionName: _normalize(institution?.name),
          ),
        );
      });

      exitSubscription = PlaidLink.onExit.listen((event) {
        final error = event.error;
        complete(
          PlaidLinkResult.exited(
            message:
                error?.displayMessage ??
                error?.message ??
                'Card linking was cancelled.',
            institutionName: _normalize(event.metadata.institution?.name),
          ),
        );
      });

      await PlaidLink.create(
        configuration: LinkTokenConfiguration(token: linkToken),
      );
      await PlaidLink.open();

      return await completer.future.timeout(
        _sessionTimeout,
        onTimeout: () async {
          // Dismiss the native Link view so a late-completed session cannot
          // surface a public token that will never be exchanged.
          try {
            await PlaidLink.close();
          } catch (_) {
            // A platform failure while closing must not mask the timeout.
          }
          return const PlaidLinkResult.failed(
            'Plaid Link timed out. Please try again.',
          );
        },
      );
    } catch (error) {
      return PlaidLinkResult.failed('Could not open Plaid Link: $error');
    } finally {
      await successSubscription?.cancel();
      await exitSubscription?.cancel();
    }
  }

  String? _normalize(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
