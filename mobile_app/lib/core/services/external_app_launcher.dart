import 'dart:io';
import 'package:android_intent_plus/android_intent.dart';
import 'package:cardsemble/core/utils/currency.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Abstract launcher for opening external apps to pay a bill.
abstract class ExternalAppLauncher {
  /// Launches the given app to pay [amount] in [currency].
  ///
  /// Formats the amount using [formatCurrency], copies it to the clipboard,
  /// then attempts to open the app via its package name (Android) or URL scheme (iOS).
  ///
  /// Throws if the app cannot be launched.
  Future<void> launchApp({
    required String packageName,
    required String scheme,
    required String amount,
    required String currency,
  });
}

/// Default implementation of [ExternalAppLauncher] that uses platform-specific
/// APIs to launch apps.
class DefaultExternalAppLauncher implements ExternalAppLauncher {
  @override
  Future<void> launchApp({
    required String packageName,
    required String scheme,
    required String amount,
    required String currency,
  }) async {
    final formatted = formatCurrency(double.parse(amount), currency);
    await Clipboard.setData(ClipboardData(text: formatted));

    if (Platform.isAndroid) {
      final intent = AndroidIntent(
        action: 'android.intent.action.MAIN',
        package: packageName,
      );
       await intent.launch();
    } else if (Platform.isIOS) {
      final uri = Uri.parse(scheme);
      if (!await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      )) {
        throw Exception('Could not launch $scheme');
      }
    } else {
      throw UnimplementedError('External app launching not supported on this platform');
    }
  }
}