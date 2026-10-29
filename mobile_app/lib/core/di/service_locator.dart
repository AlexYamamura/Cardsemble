import 'package:cardsemble/core/cache/cache_store.dart';
import 'package:cardsemble/core/cache/shared_preferences_cache_store.dart';
import 'package:cardsemble/core/network/supabase_api_client.dart';
import 'package:cardsemble/core/database/supabase_client.dart';
import 'package:cardsemble/features/auth/data/auth_repository_impl.dart';
import 'package:cardsemble/features/auth/domain/auth_repository.dart';
import 'package:cardsemble/features/auth/presentation/auth_notifier.dart';
import 'package:cardsemble/features/household/data/household_repository_impl.dart';
import 'package:cardsemble/features/household/domain/household_repository.dart';
import 'package:cardsemble/features/household/presentation/household_notifier.dart';
import 'package:cardsemble/features/transactions/data/transaction_repository_impl.dart';
import 'package:cardsemble/features/transactions/data/transaction_cache.dart';
import 'package:cardsemble/features/transactions/domain/transactions_domain.dart';
import 'package:cardsemble/features/transactions/presentation/transactions_notifier.dart';
import 'package:cardsemble/features/wallet/presentation/wallet_notifier.dart';
import 'package:cardsemble/features/card_events/data/card_event_repository_impl.dart';
import 'package:cardsemble/features/card_events/domain/card_event_repository.dart';
import 'package:cardsemble/features/card_events/presentation/card_events_notifier.dart';
import 'package:cardsemble/features/accounts/data/account_repository_impl.dart';
import 'package:cardsemble/features/accounts/data/plaid_link_launcher_impl.dart';
import 'package:cardsemble/features/accounts/domain/account_repository.dart';
import 'package:cardsemble/features/accounts/domain/plaid_link_launcher.dart';
import 'package:cardsemble/features/accounts/presentation/accounts_notifier.dart';
import 'package:cardsemble/features/device_capture/data/device_capture_repository_impl.dart';
import 'package:cardsemble/features/device_capture/domain/device_capture_repository.dart';
import 'package:cardsemble/features/device_capture/presentation/device_capture_notifier.dart';
import 'package:cardsemble/features/card_catalog/domain/card_catalog_source.dart';
import 'package:cardsemble/features/card_catalog/data/card_catalog_source_impl.dart';
import 'package:cardsemble/features/card_catalog/data/card_catalog_repository.dart';
import 'package:cardsemble/features/card_optimizer/data/card_optimizer_repository.dart';

class ServiceLocator {
  ServiceLocator._();

  static final ServiceLocator _instance = ServiceLocator._();

  static ServiceLocator get instance => _instance;

  final Map<Type, dynamic> _singletons = {};
  final Map<Type, dynamic Function()> _factories = {};

  void registerSingleton<T>(T instance) {
    _singletons[T] = instance;
  }

  void registerFactory<T>(T Function() factory) {
    _factories[T] = factory;
  }

  T get<T>() {
    if (_singletons.containsKey(T)) {
      return _singletons[T] as T;
    }
    if (_factories.containsKey(T)) {
      final instance = _factories[T]!() as T;
      _singletons[T] = instance;
      return instance;
    }
    throw StateError('No registration found for $T');
  }

  bool isRegistered<T>() =>
      _singletons.containsKey(T) || _factories.containsKey(T);

  void reset() {
    _singletons.clear();
    _factories.clear();
  }

  Future<void> initialize({
    required String supabaseBaseUrl,
    required String supabaseUrl,
    required String supabasePublishableKey,
  }) async {
    await AppSupabaseClient.initialize(
      url: supabaseUrl,
      publishableKey: supabasePublishableKey,
    );
    final supabaseClient = AppSupabaseClient.instance.client;
    final supabaseApiClient = SupabaseApiClient(
      baseUrl: supabaseBaseUrl,
      accessTokenProvider: () =>
          supabaseClient.auth.currentSession?.accessToken,
      // When a request comes back 401 (expired or revoked access token),
      // silently refresh the session using the stored refresh token and retry
      // with the new access token instead of surfacing the error to the user.
      refreshAccessToken: () async {
        await AppSupabaseClient.instance.auth.refreshSession();
        return AppSupabaseClient.instance.accessToken;
      },
    );
    registerSingleton<SupabaseApiClient>(supabaseApiClient);
    registerSingleton<AppSupabaseClient>(AppSupabaseClient.instance);

    final cacheStore = SharedPreferencesCacheStore();
    registerSingleton<CacheStore>(cacheStore);

    registerFactory<AuthRepository>(
      () => AuthRepositoryImpl(supabase: supabaseClient),
    );

    registerFactory<AuthNotifier>(
      () => AuthNotifier(
        authRepository: sl.get<AuthRepository>(),
        onBeforeSignOut: (previousUserId) async {
          if (previousUserId == null) return;
          await sl.get<TransactionCache>().clearScope(previousUserId);
        },
        onUserIdChanged: (previousUserId, nextUserId) {
          if (previousUserId == nextUserId) return;
          // Scoped keys already isolate users; this erases the old session's
          // snapshot as soon as the auth stream reports the change.
          sl.get<TransactionCache>().clearScope(previousUserId);
        },
      ),
    );

    registerFactory<HouseholdRepository>(
      () => HouseholdRepositoryImpl(apiClient: supabaseApiClient),
    );

    registerFactory<HouseholdNotifier>(
      () =>
          HouseholdNotifier(householdRepository: sl.get<HouseholdRepository>()),
    );

    registerFactory<TransactionRepository>(
      () => TransactionRepositoryImpl(apiClient: supabaseApiClient),
    );

    registerFactory<TransactionCache>(
      () => TransactionCache(
        store: cacheStore,
        scopeProvider: () => supabaseClient.auth.currentUser?.id,
        // Refresh the transaction cache at most about every 6 hours (~4 times a
        // day). Plaid writes synced transactions to Supabase on its own
        // schedule; refreshing on a cadence a bit after that means the local
        // cache catches up shortly after Plaid has updated the database.
        ttl: const Duration(hours: 6),
      ),
    );
    // Old keys were not user-scoped and cannot be attributed safely.
    await sl.get<TransactionCache>().purgeLegacyKeys();

    registerFactory<TransactionsNotifier>(
      () => TransactionsNotifier(
        transactionRepository: sl.get<TransactionRepository>(),
        loadTransactionSplitDraft: sl.get<LoadTransactionSplitDraft>(),
        saveTransactionSplit: sl.get<SaveTransactionSplit>(),
        householdRepository: sl.get<HouseholdRepository>(),
        cache: sl.get<TransactionCache>(),
      ),
    );

    registerFactory<CardEventRepository>(
      () => CardEventRepositoryImpl(
        apiClient: supabaseApiClient,
        supabase: supabaseClient,
      ),
    );

    registerFactory<CardEventsNotifier>(
      () => CardEventsNotifier(
        cardEventRepository: sl.get<CardEventRepository>(),
      ),
    );

    registerFactory<AccountRepository>(
      () => AccountRepositoryImpl(
        apiClient: supabaseApiClient,
        supabase: supabaseClient,
      ),
    );

    registerFactory<PlaidLinkLauncher>(
      () => PlaidLinkLauncherImpl(),
    );

    registerFactory<AccountsNotifier>(
      () => AccountsNotifier(
        accountRepository: sl.get<AccountRepository>(),
        linkLauncher: sl.get<PlaidLinkLauncher>(),
      ),
    );

    registerFactory<DeviceCaptureRepository>(
      () => DeviceCaptureRepositoryImpl(supabase: supabaseClient),
    );

    registerFactory<DeviceCaptureNotifier>(
      () => DeviceCaptureNotifier(
        deviceCaptureRepository: sl.get<DeviceCaptureRepository>(),
        householdRepository: sl.get<HouseholdRepository>(),
      ),
    );

    // Card catalog
    registerFactory<CardCatalogSource>(
      () => CardCatalogSourceImpl(apiClient: sl.get<SupabaseApiClient>()),
    );
    registerFactory<CardCatalogRepository>(
      () => CardCatalogRepository(
        store: sl.get<CacheStore>(),
        source: sl.get<CardCatalogSource>(),
      ),
    );

    registerFactory<CardOptimizerRepository>(() => CardOptimizerRepository());

    registerFactory<WalletNotifier>(
      () => WalletNotifier(
        accounts: sl.get<AccountsNotifier>(),
        catalog: sl.get<CardCatalogRepository>(),
        transactions: sl.get<TransactionsNotifier>(),
      ),
    );

    // Use cases
    registerFactory<LoadTransactionSplitDraft>(
      () => LoadTransactionSplitDraft(sl.get<TransactionRepository>()),
    );
    registerFactory<SaveTransactionSplit>(
      () => SaveTransactionSplit(sl.get<TransactionRepository>()),
    );
  }
}

final sl = ServiceLocator.instance;
