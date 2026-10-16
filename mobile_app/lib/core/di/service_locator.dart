import '../../core/network/api_client.dart';
import '../../core/database/supabase_client.dart';
import '../../features/auth/data/auth_repository_impl.dart';
import '../../features/auth/domain/auth_repository.dart';
import '../../features/auth/presentation/auth_notifier.dart';
import '../../features/household/data/household_repository_impl.dart';
import '../../features/household/domain/household_repository.dart';
import '../../features/household/presentation/household_notifier.dart';
import '../../features/transactions/data/transaction_repository_impl.dart';
import '../../features/transactions/data/transaction_cache.dart';
import '../../features/transactions/domain/transaction_repository.dart';
import '../../features/transactions/presentation/transactions_notifier.dart';
import '../../features/card_events/data/card_event_repository_impl.dart';
import '../../features/card_events/domain/card_event_repository.dart';
import '../../features/card_events/presentation/card_events_notifier.dart';
import '../../features/accounts/data/account_repository_impl.dart';
import '../../features/accounts/domain/account_repository.dart';
import '../../features/accounts/presentation/accounts_notifier.dart';
import '../../features/device_capture/data/device_capture_repository_impl.dart';
import '../../features/device_capture/domain/device_capture_repository.dart';
import '../../features/device_capture/presentation/device_capture_notifier.dart';

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

  bool isRegistered<T>() => _singletons.containsKey(T) || _factories.containsKey(T);

  void reset() {
    _singletons.clear();
    _factories.clear();
  }

  Future<void> initialize({
    required String apiBaseUrl,
    required String supabaseUrl,
    required String supabasePublishableKey,
  }) async {
    await AppSupabaseClient.initialize(
      url: supabaseUrl,
      publishableKey: supabasePublishableKey,
    );
    final supabaseClient = AppSupabaseClient.instance.client;
    final apiClient = ApiClient(
      baseUrl: apiBaseUrl,
      accessTokenProvider: () => supabaseClient.auth.currentSession?.accessToken,
    );
    registerSingleton<ApiClient>(apiClient);
    registerSingleton<AppSupabaseClient>(AppSupabaseClient.instance);

    registerFactory<AuthRepository>(() => AuthRepositoryImpl(
          supabase: supabaseClient,
        ));

    registerFactory<AuthNotifier>(() => AuthNotifier(
          authRepository: sl.get<AuthRepository>(),
        ));

    registerFactory<HouseholdRepository>(() => HouseholdRepositoryImpl(
          apiClient: apiClient,
        ));

    registerFactory<HouseholdNotifier>(() => HouseholdNotifier(
          householdRepository: sl.get<HouseholdRepository>(),
        ));

    registerFactory<TransactionRepository>(() => TransactionRepositoryImpl(
          apiClient: apiClient,
        ));

    registerFactory<TransactionCache>(() => TransactionCache());

    registerFactory<TransactionsNotifier>(() => TransactionsNotifier(
          transactionRepository: sl.get<TransactionRepository>(),
          householdRepository: sl.get<HouseholdRepository>(),
          cache: sl.get<TransactionCache>(),
        ));

    registerFactory<CardEventRepository>(() => CardEventRepositoryImpl(
          apiClient: apiClient,
          supabase: supabaseClient,
        ));

    registerFactory<CardEventsNotifier>(() => CardEventsNotifier(
          cardEventRepository: sl.get<CardEventRepository>(),
        ));

    registerFactory<AccountRepository>(() => AccountRepositoryImpl(
          apiClient: apiClient,
          supabase: supabaseClient,
        ));

    registerFactory<AccountsNotifier>(() => AccountsNotifier(
          accountRepository: sl.get<AccountRepository>(),
        ));

    registerFactory<DeviceCaptureRepository>(() => DeviceCaptureRepositoryImpl(
          supabase: supabaseClient,
        ));

    registerFactory<DeviceCaptureNotifier>(() => DeviceCaptureNotifier(
          deviceCaptureRepository: sl.get<DeviceCaptureRepository>(),
          householdRepository: sl.get<HouseholdRepository>(),
        ));
  }
}

final sl = ServiceLocator.instance;