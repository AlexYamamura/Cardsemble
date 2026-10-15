import 'package:supabase_flutter/supabase_flutter.dart';

class AppSupabaseClient {
  AppSupabaseClient._(this._client);

  final SupabaseClient _client;

  static AppSupabaseClient? _instance;

  static AppSupabaseClient get instance {
    if (_instance == null) {
      throw StateError('AppSupabaseClient not initialized. Call initialize() first.');
    }
    return _instance!;
  }

  static Future<void> initialize({
    required String url,
    required String publishableKey,
  }) async {
    await Supabase.initialize(
      url: url,
      publishableKey: publishableKey,
    );
    _instance = AppSupabaseClient._(Supabase.instance.client);
  }

  SupabaseClient get client => _client;

  GoTrueClient get auth => _client.auth;

  // Use the client directly for database operations
  SupabaseClient get database => _client;

  RealtimeClient get realtime => _client.realtime;

  SupabaseStorageClient get storage => _client.storage;

  FunctionsClient get functions => _client.functions;

  String? get currentUserId => _client.auth.currentUser?.id;

  Session? get currentSession => _client.auth.currentSession;

  String? get accessToken => _client.auth.currentSession?.accessToken;

  bool get isSignedIn => _client.auth.currentSession != null;
}