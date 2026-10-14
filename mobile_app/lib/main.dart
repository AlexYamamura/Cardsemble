import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'ledger_api.dart';
import 'ledger_screen.dart';

const _apiBaseUrl = String.fromEnvironment(
  'CARD_EVENTS_API_URL',
  defaultValue: 'https://ebawvkiabuhcyvyzegfn.supabase.co/functions/v1/api',
);
const _oauthRedirectUrl = 'com.plaidtest.cardsemble://login-callback/';

void main() {
  runApp(const CardsembleApp());
}

class CardsembleApp extends StatefulWidget {
  const CardsembleApp({super.key});

  @override
  State<CardsembleApp> createState() => _CardsembleAppState();
}

class _CardsembleAppState extends State<CardsembleApp> {
  late Future<SupabaseClient> _client;

  @override
  void initState() {
    super.initState();
    _client = _initializeSupabase();
  }

  Future<SupabaseClient> _initializeSupabase() async {
    final response = await http.get(
      Uri.parse('$_apiBaseUrl/api/public-config'),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Could not load app configuration (HTTP ${response.statusCode}).',
      );
    }

    final config = jsonDecode(response.body) as Map<String, dynamic>;
    await Supabase.initialize(
      url: config['supabase_url'] as String,
      publishableKey: config['supabase_publishable_key'] as String,
    );
    return Supabase.instance.client;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cardsemble',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF244A3A),
          surface: const Color(0xFFF3EFE6),
        ),
        useMaterial3: true,
      ),
      home: FutureBuilder<SupabaseClient>(
        future: _client,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _StartupError(
              message: snapshot.error.toString(),
              onRetry: () => setState(() {
                _client = _initializeSupabase();
              }),
            );
          }
          if (!snapshot.hasData) {
            return const _LoadingScreen();
          }
          return _SessionGate(client: snapshot.data!, apiBaseUrl: _apiBaseUrl);
        },
      ),
    );
  }
}

class _SessionGate extends StatefulWidget {
  const _SessionGate({required this.client, required this.apiBaseUrl});

  final SupabaseClient client;
  final String apiBaseUrl;

  @override
  State<_SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<_SessionGate> {
  Session? _session;
  bool _signingIn = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _session = widget.client.auth.currentSession;
    widget.client.auth.onAuthStateChange.listen((change) {
      if (!mounted) return;
      setState(() {
        _session = change.session;
        _error = null;
      });
    });
  }

  Future<void> _signIn() async {
    setState(() {
      _signingIn = true;
      _error = null;
    });
    try {
      await widget.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: _oauthRedirectUrl,
      );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  Future<void> _signOut() async {
    await widget.client.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    if (session == null) {
      return _SignInScreen(
        signingIn: _signingIn,
        error: _error,
        onSignIn: _signIn,
      );
    }

    return LedgerScreen(
      api: HybridLedgerApi(
        baseUrl: widget.apiBaseUrl,
        supabase: widget.client,
        accessToken: () => widget.client.auth.currentSession?.accessToken,
      ),
      onSignOut: _signOut,
    );
  }
}

class _SignInScreen extends StatelessWidget {
  const _SignInScreen({
    required this.signingIn,
    required this.error,
    required this.onSignIn,
  });

  final bool signingIn;
  final String? error;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colorScheme.primaryContainer.withAlpha(60),
              colorScheme.secondaryContainer.withAlpha(40),
              colorScheme.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Hero illustration
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            colorScheme.primary,
                            colorScheme.primary.withAlpha(200),
                            colorScheme.secondary,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(36),
                        boxShadow: [
                          BoxShadow(
                            color: colorScheme.primary.withAlpha(60),
                            blurRadius: 30,
                            offset: const Offset(0, 12),
                            spreadRadius: -4,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.account_balance_wallet_rounded,
                        size: 60,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 32),
                    // Title
                    ShaderMask(
                      shaderCallback: (bounds) => LinearGradient(
                        colors: [colorScheme.primary, colorScheme.secondary],
                      ).createShader(bounds),
                      child: Text(
                        'Cardsemble',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Subtitle
                    Text(
                      'Track shared card spending, assign every charge, '
                      'and settle up with confidence.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 40),
                    // Sign in button
                    FilledButton.icon(
                      onPressed: signingIn ? null : onSignIn,
                      icon: signingIn
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation(Colors.white),
                              ),
                            )
                          : const Icon(Icons.login_rounded, size: 22),
                      label: Text(
                        signingIn ? 'Opening sign-in…' : 'Continue with Google',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(double.infinity, 56),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: colorScheme.primary,
                        foregroundColor: colorScheme.onPrimary,
                      ),
                    ),
                    // Features hints
                    const SizedBox(height: 32),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _FeaturePill(
                          icon: Icons.insights_rounded,
                          label: 'Smart summaries',
                          colorScheme: colorScheme,
                        ),
                        _FeaturePill(
                          icon: Icons.receipt_long_rounded,
                          label: 'Auto-capture',
                          colorScheme: colorScheme,
                        ),
                        _FeaturePill(
                          icon: Icons.group_rounded,
                          label: 'Split fairly',
                          colorScheme: colorScheme,
                        ),
                      ],
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 24),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: colorScheme.error.withAlpha(80),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.error_outline_rounded,
                              color: colorScheme.error,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                error!,
                                style: TextStyle(
                                  color: colorScheme.onErrorContainer,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FeaturePill extends StatelessWidget {
  const _FeaturePill({
    required this.icon,
    required this.label,
    required this.colorScheme,
  });

  final IconData icon;
  final String label;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withAlpha(180),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colorScheme.outline.withAlpha(60)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
