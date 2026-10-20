import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:cardsemble/core/core.dart';
import 'package:cardsemble/app/config/env.dart';
import 'package:cardsemble/theme/app_colors.dart';
import 'package:cardsemble/app/router/app_router.dart';
import 'package:cardsemble/features/auth/presentation/auth_notifier.dart';
import 'package:cardsemble/features/auth/presentation/auth_wrapper.dart';
import 'package:cardsemble/features/accounts/presentation/accounts_notifier.dart';
import 'package:cardsemble/features/card_events/presentation/card_events_notifier.dart';
import 'package:cardsemble/features/device_capture/presentation/device_capture_notifier.dart';
import 'package:cardsemble/features/household/presentation/household_notifier.dart';
import 'package:cardsemble/features/transactions/presentation/transactions_notifier.dart';

class CardsembleApp extends StatefulWidget {
  const CardsembleApp({super.key});

  @override
  State<CardsembleApp> createState() => _CardsembleAppState();
}

class _CardsembleAppState extends State<CardsembleApp> {
  late Future<void> _initialization;

  @override
  void initState() {
    super.initState();
    _initialization = _initialize();
  }

  Future<void> _initialize() async {
    try {
       final response = await http.get(Uri.parse('$supabaseBaseUrl/api/public-config'));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          'Could not load app configuration (HTTP ${response.statusCode}).',
        );
      }

      final config = jsonDecode(response.body) as Map<String, dynamic>;
      final supabaseUrl = config['supabase_url'] as String;
      final supabasePublishableKey = config['supabase_publishable_key'] as String;

      await sl.initialize(
         supabaseBaseUrl: supabaseBaseUrl,
        supabaseUrl: supabaseUrl,
        supabasePublishableKey: supabasePublishableKey,
      );
    } catch (e, stack) {
      debugPrint('Initialization error: $e');
      debugPrint('Stack: $stack');
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _initialization,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return MaterialApp(
            title: 'Cardsemble',
            theme: _theme(),
            home: _StartupError(
              message: snapshot.error.toString(),
              onRetry: () => setState(() => _initialization = _initialize()),
            ),
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return MaterialApp(
            title: 'Cardsemble',
            theme: _theme(),
            home: const _LoadingScreen(),
          );
        }
        return MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthNotifier>(
              create: (_) => sl.get<AuthNotifier>(),
            ),
            ChangeNotifierProvider<HouseholdNotifier>(
              create: (_) => sl.get<HouseholdNotifier>(),
            ),
            ChangeNotifierProvider<TransactionsNotifier>(
              create: (_) => sl.get<TransactionsNotifier>(),
            ),
            ChangeNotifierProvider<CardEventsNotifier>(
              create: (_) => sl.get<CardEventsNotifier>(),
            ),
            ChangeNotifierProvider<AccountsNotifier>(
              create: (_) => sl.get<AccountsNotifier>(),
            ),
            ChangeNotifierProvider<DeviceCaptureNotifier>(
              create: (_) => sl.get<DeviceCaptureNotifier>(),
            ),
          ],
          child: MaterialApp(
            title: 'Cardsemble',
            theme: _theme(),
            home: const AuthWrapper(child: MainTabs()),
          ),
        );
      },
    );
  }

   ThemeData _theme() {
     return ThemeData(
       useMaterial3: true,
       colorScheme: ColorScheme.light(
         primary: AppColors.primary,
         primaryContainer: AppColors.primaryDark,
         secondary: AppColors.sand,
         secondaryContainer: AppColors.cream,
         surface: AppColors.surface,
         error: AppColors.error,
         onPrimary: AppColors.onPrimary,
         onSecondary: AppColors.charcoal,
         onSurface: AppColors.onSurface,
         onError: AppColors.onError,
         outline: AppColors.outline,
       ),
       datePickerTheme: DatePickerThemeData(
         rangeSelectionBackgroundColor: Color.alphaBlend(AppColors.primary.withValues(alpha: 0.24), AppColors.surface),
       ),
       scaffoldBackgroundColor: AppColors.background,
       appBarTheme: AppBarTheme(
         backgroundColor: AppColors.primary,
         foregroundColor: AppColors.onPrimary,
         elevation: 0,
         centerTitle: true,
         titleTextStyle: const TextStyle(
           color: Colors.white,
           fontSize: 20,
           fontWeight: FontWeight.w600,
         ),
       ),
     );
   }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            const Text('Initializing...'),
          ],
        ),
      ),
    );
  }
}

class _StartupError extends StatelessWidget {
  const _StartupError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 40),
              const SizedBox(height: 12),
              const Text('Could not connect to the card service.'),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: onRetry, child: const Text('Try again')),
            ],
          ),
        ),
      ),
    );
  }
}
