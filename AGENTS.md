# Cardsemble Agent Guide

Cardsemble is a Flutter household credit-card tracker backed by a Supabase Edge Function, Supabase Postgres/RLS, and Plaid. The app captures Google Wallet notifications on Android (and accepts external card events from an iPhone Shortcut), syncs Plaid transactions, lets people assign/split charges, and shows spending summaries.

This file is a navigation map, not a specification. Verify behavior in the cited source before changing it. Last inspected against the working tree on 2026-10-26.

## Repository Map

| Path | Purpose |
|---|---|
| `mobile_app/` | Flutter app. Run all Flutter commands from this directory. |
| `mobile_app/lib/main.dart` | Minimal entry point; runs `CardsembleApp`. |
| `mobile_app/lib/app/` | App bootstrap (`app.dart`), environment constants (`config/env.dart`), and the actual shell/navigation (`router/app_router.dart`, which contains `MainTabs`, not a `go_router` table). |
| `mobile_app/lib/core/` | Cross-cutting layers: dependency injection, Supabase client, authenticated HTTP client, `Result`/`Failure` types, cache primitives, date/currency helpers, external-app launcher. |
| `mobile_app/lib/core/cache/` | Shared cache primitives: `CacheStore`/`SharedPreferencesCacheStore`, `CacheRecord`, `CachedRepository<K,V>`, TTL defaults, clock/scope injection. |
| `mobile_app/lib/features/card_catalog/` | Card catalog reference model and `CachedRepository` child. `CardCatalogSource` is an unimplemented integration boundary; no backend table/route exists. |
| `mobile_app/lib/features/<feature>/domain/` | Entities, repository interfaces, use cases, split arithmetic. Pure Dart; no Flutter UI except `DateTimeRange` in transaction queries. |
| `mobile_app/lib/features/<feature>/data/` | Repository implementations, direct Supabase queries, and `SharedPreferences` cache. |
| `mobile_app/lib/features/<feature>/presentation/` | `ChangeNotifier` state holders and screens/widgets. |
| `mobile_app/lib/features/` | Features: `auth`, `household`, `transactions`, `summary`, `accounts`, `card_events`, `card_catalog`, `device_capture`, `wallet`. |
| `mobile_app/test/` | Flutter unit/widget tests. No `integration_test/` directory exists. |
| `mobile_app/android/` | Android host, notification-listener capture service, Gradle config, and instrumented parser tests. |
| `mobile_app/ios/`, `web/`, `windows/`, etc. | Platform scaffolds. Native capture is implemented only for Android. |
| `supabase/functions/api/` | Single Deno Edge Function serving the app API (`index.ts`). |
| `supabase/functions/_shared/` | Shared backend modules: auth/device tokens, Plaid, reconciliation/statement math, merchant normalization, types, service-role Supabase client. |
| `supabase/migrations/` | Incremental schema, grant, and RLS migrations. They assume the base tables already exist. |
| `supabase/config.toml` | Local Supabase/function configuration. `functions.api` has `verify_jwt = false`; the function authenticates requests itself. |
| `card-events-api/` | Legacy FastAPI service plus `card_events.sql`, which is the canonical full base schema/policies for the Supabase tables. The Edge Function has replaced runtime use of the FastAPI app. |
| Root Python files (`cloud_store.py`, `analyze_csv.py`, `transactions.db`) | Developer/legacy utilities and local data. Not imported by the Flutter app. |

Flutter dependencies declared in `mobile_app/pubspec.yaml` include `provider`, `supabase_flutter`, `http`, `shared_preferences`, `crypto`, `mobile_scanner`, `qr_flutter`, `android_intent_plus`, `url_launcher`, and `plaid_flutter`. `plaid_flutter` is used only by `features/accounts/data/plaid_link_launcher_impl.dart`.

## Key Files and Functions

### App shell, core, and transactions

| File | Important symbols | Responsibility / when to inspect | Inspect together with |
|---|---|---|---|
| `mobile_app/lib/app/app.dart` | `CardsembleApp`, `_CardsembleAppState._initialize`, `_theme` | Fetches `GET {apiBaseUrl}/api/public-config`, initializes Supabase/DI, installs all `ChangeNotifier` providers, wraps the shell in `AuthWrapper`. Change here for startup/provider wiring. | `app/config/env.dart`, `core/di/service_locator.dart`, `auth/presentation/auth_wrapper.dart` |
| `mobile_app/lib/app/config/env.dart` | `apiBaseUrl`, `oauthRedirectUrl`, `settingsReviewedKey` | Compile-time API base (`CARD_EVENTS_API_URL`, default Supabase `.../functions/v1/api`) and OAuth redirect. | `app.dart`, `auth_notifier.dart`, `app_router.dart` |
| `mobile_app/lib/app/router/app_router.dart` | `MainTabs`, `_MainTabsState`, `_AnimatedTabBar`, `_KeepAliveTab`, `NavigatorPopHandler` | The real app shell: `PageView` tabs with per-tab navigators Summary/Transactions/Events/People, custom bottom bar with active-tab back dispatch. Settings and first-run setup are routed screens (`CaptureSettingsScreen`). `_autoConfigureStep1` logic moved to `DeviceCaptureNotifier`. | `summary_screen.dart`, `transactions_screen.dart`, `card_events_screen.dart`, `people_screen.dart`, `DeviceCaptureNotifier`, `CaptureSettingsScreen` |
| `mobile_app/lib/core/di/service_locator.dart` | `ServiceLocator`, `sl`, `initialize`, `registerFactory`, `get` | Hand-rolled singleton/factory registry. `initialize` creates `ApiClient`, Supabase, repositories, notifiers, and split use cases. Factories are cached as singletons on first `get`. | All repository/notifier constructors; `app.dart` |
| `mobile_app/lib/core/network/api_client.dart` | `ApiClient`, `get/post/patch/delete`, `safeGet/safePost/safePatch/safeDelete`, `extractRecords` | Adds the Supabase bearer token, maps non-2xx responses to `NetworkException` (using the JSON `detail` field), and converts exceptions into `Result` failures. | `core/error/failure.dart`, all `*_repository_impl.dart`, `supabase/functions/api/index.ts` |
| `mobile_app/lib/core/error/failure.dart` | `Result<T>`, `Success`, `FailureResult`, `Failure` subclasses, `ResultExtensions.map/flatMap` | Error/result contract used by every repository and notifier. Preserve this API when changing service boundaries. | repository implementations, notifiers |
| `mobile_app/lib/core/database/supabase_client.dart` | `AppSupabaseClient.initialize`, `instance`, `client`, `auth`, `database` | Initializes the Supabase Flutter singleton and exposes auth/database/realtime/storage/functions. | `app.dart`, direct-Supabase repositories |
| `mobile_app/lib/features/transactions/domain/entities/transaction.dart` | `CardTransaction`, `TransactionAssignment`, `TransactionQuery`, `TransactionPage`, `TransactionSplit` | Wire/domain models for the ledger, assignments, and splits. `CardTransaction.fromJson` defines the exact server field names. Previously contained CSV import models, now removed. | repository impl, notifier, cache, summary/transactions screens |
| `mobile_app/lib/features/transactions/domain/transaction_repository.dart` | `TransactionRepository` | Repository interface for loading the ledger, assignments/splits, and visibility. | `transaction_repository_impl.dart`, notifier, use cases |
| `mobile_app/lib/features/transactions/data/transaction_repository_impl.dart` | `loadTransactions`, `loadAccounts`, `assignTransaction`, `assignTransactionSplit`, `fetchTransactionSplits`, `setHouseholdVisible` | Maps `TransactionRepository` calls to Edge Function routes and parses responses. Most routes are under `/api/plaid-transactions` and `/api/owed`. | `supabase/functions/api/index.ts`, `transaction.dart`, tests |
| `mobile_app/lib/features/transactions/presentation/transactions_notifier.dart` | `TransactionsNotifier`, `SummaryRow`, `loadAll`, `_runLoadAll`, `loadTransactions`, `loadMoreTransactions`, `loadSummaryTransactions`, `loadPeople`, `loadAccounts`, `assignTransaction`, `saveTransactionSplit`, `setHouseholdVisible`, `loadSplitDraft`, `filteredTransactions`, `filteredTotalsByCurrency`, `refresh` | Single owner of ledger list, summary list, date/account/person filters, split-draft cache, and cached people/accounts. Contains generation counters and request coalescing. Start here for most transaction-state changes. | screen, summary, cache, split use cases, repo |
| `mobile_app/lib/features/transactions/presentation/transactions_screen.dart` | `TransactionsScreen`, `_TransactionFilterBar`, `_TransactionTile`, `_SplitSection`, `_UnifiedSplitSliderBuilder`, `_runAssignment`, `_runSplit`, `_runVisibility`, `_refresh` | Ledger UI: filters, date chips, assignment selector, household-visibility switch, expandable split editor, paging trigger. | notifier, `split_math.dart`, `unified_split_slider.dart` |
| `mobile_app/lib/features/transactions/domain/split_math.dart` | `equalSplitPercentages`, `percentagesFromExistingSplits`, `moveBoundary`, `snapToGuideline`, `percentagesToCents` | Pure split arithmetic. `percentagesToCents` is the cent-exact authority used before persistence. | split use cases, `_SplitSection`, `split_math_test.dart` |
| `mobile_app/lib/features/transactions/domain/use_cases/load_transaction_split_draft.dart` | `LoadTransactionSplitDraft.call` | Fetches existing splits; converts to normalized percentages, falling back to equal split when absent/invalid. | repo `fetchTransactionSplits`, `split_math.dart` |
| `mobile_app/lib/features/transactions/domain/use_cases/save_transaction_split.dart` | `SaveTransactionSplit.call` | Validates participants, 100% sum, positive total, and exact cent totals, then persists splits. | repo `assignTransactionSplit`, `split_math.dart` |
| `mobile_app/lib/core/cache/cache_store.dart` | `CacheStore`, `CacheRecord`, `CacheClock`, `CacheScopeProvider`, `kDefaultCacheTtl` | Storage/freshness contract. `SharedPreferencesCacheStore` persists one versioned JSON envelope per key with scope and timestamp; corrupt or wrong-scope entries read as misses. | `cached_repository.dart`, `transaction_cache.dart`, tests |
| `mobile_app/lib/core/cache/cached_repository.dart` | `CachedRepository<K,V>`, `CacheBatchResult` | Reusable cache-first parent: overridable TTL (24h default), batched missing/expired fetches, write-back, stale-on-error, partial-response handling, scoped invalidation, late-response rejection. | `CardCatalogRepository`, `cache_store.dart` |
| `mobile_app/lib/features/transactions/data/transaction_cache.dart` | `TransactionCache`, `TransactionCacheSnapshot`, `CachedSection` | Per-user transaction snapshot in one SharedPreferences key. Four independently timestamped sections, serialized read-modify-write queue, corrupt-section isolation, 24h freshness metadata, legacy-key purge. | notifier `_hydrateFromCache`/`_writeCache`, `clearCache` |
| `mobile_app/lib/features/card_catalog/domain/entities/card_catalog_card.dart` | `CardCatalogCard`, fee/APR/rewards/benefit/perk models | Typed reference-data model matching the supplied catalog JSON shape; unknown keys survive in `extra`. | `card_catalog_source.dart`, repository tests |
| `mobile_app/lib/features/card_catalog/domain/card_catalog_source.dart` | `CardCatalogSource` | Integration boundary for the future catalog backend (`fetchCards`, `searchCards`). No table/route exists yet. | `card_catalog_repository.dart` |
| `mobile_app/lib/features/card_catalog/data/card_catalog_repository.dart` | `CardCatalogRepository extends CachedRepository<String, CardCatalogCard>` | Per-card cache keyed by stable catalog id, global scope, 24h default TTL, batch fetch, search write-through. Does not cache selections or account-specific benefit usage. | `cached_repository.dart`, `card_catalog_source.dart` |
| `mobile_app/lib/features/transactions/presentation/widgets/unified_split_slider.dart` | `UnifiedSplitSlider`, `ParticipantInfo`, `_handleDragUpdate` | Drag boundaries for 2-4 participants, snapping to 25/50/75 and keeping the total at 100%. | `split_math.dart`, `_SplitSection` |
| `mobile_app/lib/features/transactions/presentation/widgets/pay_action_sheet.dart` | `PayButton`, `_showPayActionSheet`, `_handlePress`, `_handleCopy` | Opens Fidelity/Chase/Venmo apps with the filtered amount or copies the amount. No payment API is involved. | `TransactionsNotifier.filteredTotal`, `core/services/external_app_launcher.dart` |

### Summary, household, accounts, auth, events, capture

| File | Important symbols | Responsibility / when to inspect | Inspect together with |
|---|---|---|---|
| `mobile_app/lib/features/summary/presentation/summary_screen.dart` | `SummaryScreen`, `_buildSummaryContent`, `_selectMonth`, `_chooseSummaryRange`, `_drilldownIntoTransactions`, `_editCardName`, `_importCsv`, `_showImportPreviewDialog`, `_buildImportPreviewSections`, `_buildImportSection`, `_refresh` | Monthly spending dashboard and CSV import entry point. Computes local totals from `summaryTransactions` (positive, posted, non-payment charges), drills into the Transactions tab by setting filters. Import preview shows New/Suggested/Confirmed-Duplicate sections with confidence tiers. | notifier, accounts, CSV backend, transaction repo |
| `mobile_app/lib/features/household/domain/entities/household.dart` | `HouseholdPerson`, `HouseholdMember`, `JoinHouseholdResult` | Person/member models. `HouseholdPerson.fromJson` accepts `person_id` or `id`. | household repo/notifier, people screen, device capture |
| `mobile_app/lib/features/household/domain/household_repository.dart` | `HouseholdRepository` | Interface for people CRUD, member listing/addition, invite-code join. | `household_repository_impl.dart` |
| `mobile_app/lib/features/household/data/household_repository_impl.dart` | `loadPeople`, `createPerson`, `updatePerson`, `deletePerson`, `loadMembers`, `addMember`, `joinByInviteCode` | Calls `/api/household/people` and `/api/household/members*` through `ApiClient`. | `supabase/functions/api/index.ts` household routes |
| `mobile_app/lib/features/household/presentation/household_notifier.dart` | `HouseholdNotifier`, `loadPeople`, `loadMembers`, `createPerson`, `updatePerson`, `deletePerson`, `addMember`, `joinByInviteCode`, `filteredPeople` | Owns a separate people/members list used by People/Members/Invite screens. Mutations do not automatically refresh `TransactionsNotifier.people` or `DeviceCaptureNotifier.people`. | people/members/invite screens, transactions notifier |
| `mobile_app/lib/features/household/presentation/people_screen.dart` | `PeopleScreen`, `_buildQrPlaceholder`, `_scanQrCode`, `_processScannedCode`, `_showAddPersonDialog`, `_setDefault` | Manage household people. QR flow first tries `addMember(scannedCode)`, then `joinByInviteCode(scannedCode)`. | household notifier/repository, `mobile_scanner` |
| `mobile_app/lib/features/household/presentation/members_screen.dart` | `MembersScreen` | Lists members and adds by raw user ID. Not instantiated anywhere in the inspected app. | household notifier/repository |
| `mobile_app/lib/features/household/presentation/invite_screen.dart` | `InviteScreen` | Form to join by invite code. Not instantiated anywhere in the inspected app. | household notifier/repository |
| `mobile_app/lib/features/auth/data/auth_repository_impl.dart` | `AuthRepositoryImpl.getCurrentSession`, `signInWithGoogle`, `signOut`, `authStateChanges` | Supabase Google OAuth and session stream. | `auth_notifier.dart`, `app.dart`, Android/iOS URL config |
| `mobile_app/lib/features/auth/presentation/auth_notifier.dart` | `AuthNotifier`, `initialize`, `signInWithGoogle`, `signOut`, `updateSession` | Session state for the UI. `AuthWrapper` calls `initialize()` after first frame. | `auth_wrapper.dart`, `sign_in_screen.dart` |
| `mobile_app/lib/features/auth/presentation/auth_wrapper.dart` | `AuthWrapper` | Shows loading/sign-in or the main shell based on `AuthNotifier.isAuthenticated`. | `auth_notifier.dart`, `sign_in_screen.dart` |
| `mobile_app/lib/features/accounts/data/account_repository_impl.dart` | `loadPlaidConnections`, `createPlaidLinkToken`, `syncPlaidConnections`, `exchangePlaidPublicToken`, `updateCreditCardDisplayName`, `loadStatementCycles` | Mixed persistence: `plaid_items`/`plaid_credit_accounts` reads/writes go directly through Supabase; Plaid link/sync/statement-cycle calls go through the API. | `accounts_notifier.dart`, `_shared/plaid.ts`, `api/index.ts` |
| `mobile_app/lib/features/accounts/domain/plaid_link_launcher.dart` | `PlaidLinkStatus`, `PlaidLinkResult`, `PlaidLinkLauncher` | Pure-Dart boundary for opening Plaid Link. `PlaidLinkResult` carries the public token, institution id/name, and a failure message. | `plaid_link_launcher_impl.dart`, `accounts_notifier.dart` |
| `mobile_app/lib/features/accounts/domain/entities/plaid_sync_outcome.dart` | `PlaidSyncOutcome`, `PlaidItemSyncError` | Parses the backend sync result's `item_errors` payload. Tolerant of a missing/non-list `item_errors` and skips malformed rows. | `account_repository_impl.dart`, `accounts_notifier.dart` |
| `mobile_app/lib/features/accounts/data/plaid_link_launcher_impl.dart` | `PlaidLinkLauncherImpl.launch` | The only file that imports `package:plaid_flutter`. Subscribes to the static `PlaidLink.onSuccess`/`onExit` streams, then creates and opens the Link session; maps the first event to a `PlaidLinkResult`, closes the native Link view and fails after a 5-minute timeout. | `plaid_link_launcher.dart` |
| `mobile_app/lib/features/accounts/presentation/accounts_notifier.dart` | `AccountsNotifier`, `loadConnections`, `loadStatementCycles`, `createLinkToken`, `linkAccount`, `syncConnections`, `exchangePublicToken`, `updateDisplayName`, `isLinking`, `lastLinkedInstitutionName`, `warning`, `clearWarning` | Owns connection list and statement summary. `linkAccount` runs the shared link flow: link token -> Plaid Link -> `exchangePublicToken` -> reload connections and statement cycles. Has a dedicated `warning` channel (separate from `error`) for non-fatal outcomes such as per-item Plaid sync errors. | accounts screen/repo, `plaid_link_launcher.dart` |
| `mobile_app/lib/features/accounts/presentation/accounts_screen.dart` | `AccountsScreen`, `_linkNewAccount`, `_syncAccounts`, `_editDisplayName`, `_buildStatementSection` | Connection/statement UI. `_linkNewAccount` runs `AccountsNotifier.linkAccount()` and shows a success/error SnackBar; the "Link Account" FAB is disabled while linking. This screen currently has no entry point in the app shell: the Summary "Link a card" button runs the same link flow in place instead of navigating here. | accounts notifier/repo, Plaid backend |
| `mobile_app/lib/features/card_events/domain/entities/card_event.dart` | `CardEventRecord` | Captured Wallet/Shortcut event model. It has no `householdVisible` field; `reconciliationStatus` carries a reconciliation status string. | repository, notifier, screen |
| `mobile_app/lib/features/card_events/data/card_event_repository_impl.dart` | `loadCardEvents`, `setHouseholdVisible` | Reads `card_events` and `card_event_reconciliations` directly via Supabase; visibility update uses the API PATCH route. | migrations, `api/index.ts`, reconcile |
| `mobile_app/lib/features/card_events/presentation/card_events_notifier.dart` | `CardEventsNotifier.loadEvents`, `setHouseholdVisible` | Loads at most 200 events for the current user; on visibility success it rebuilds the local record but does not change any field. | card events repo/screen |
| `mobile_app/lib/features/card_events/presentation/card_events_screen.dart` | `CardEventsScreen`, `_EventTile`, `_SourceBadge`, `_ReconciliationBadge` | Event feed UI. Derives "household visible" from `reconciliationStatus == 'household_visible'`, which is not a documented backend reconciliation status. | card events notifier/repo, reconcile statuses |
| `mobile_app/lib/features/device_capture/data/device_capture_repository_impl.dart` | `createGooglePayDeviceToken`, `revokeDeviceToken`, `isConfigured`, `hasNotificationAccess`, `openNotificationAccessSettings`, `sendTestNotification`, `getDeviceId`, `configure`, `clear` | Generates a SHA-256 device token, inserts `device_tokens` directly via Supabase, and drives the Android `MethodChannel` `com.plaidtest.cardsemble/google_pay_capture`. | `MainActivity.kt`, `CaptureCredentialStore.kt`, `DeviceCaptureNotifier` |
| `mobile_app/lib/features/device_capture/presentation/device_capture_notifier.dart` | `DeviceCaptureNotifier`, `loadPeople`, `checkStatus`, `createDeviceToken`, `configureCapture`, `sendTestNotification`, `revokeDeviceToken`, `clearCapture` | Capture setup state. `configureCapture` stores the API URL/token/device ID in native secure storage. | `app_router.dart` settings overlay, native files |
| `mobile_app/lib/features/device_capture/presentation/device_capture_screen.dart` | `DeviceCaptureScreen` | Standalone capture UI; not instantiated anywhere. The active setup UI is now in `CaptureSettingsScreen` (settings and first-run setup). | `app_router.dart`, `DeviceCaptureNotifier` |
| `mobile_app/lib/features/device_capture/presentation/capture_settings_screen.dart` | `CaptureSettingsScreen` | Routed screen for Settings and first-run setup. Handles auto-configuration of device token and notification access. | `app_router.dart`, `DeviceCaptureNotifier` |
| `mobile_app/lib/features/device_capture/presentation/settings_step.dart` | `SettingsStep` | Presentational step row used by the capture setup overlay. | `app_router.dart` |
| `mobile_app/android/app/src/main/kotlin/com/plaidtest/cardsemble/GooglePayNotificationListenerService.kt` | `GooglePayNotificationListenerService`, `onNotificationPosted`, `parseTransaction`, `sendEvent`, `wasAlreadySent`, `rememberSent` | Listens only to `com.google.android.apps.walletnfcrel` (and its own test notification), parses amount/currency/card, deduplicates by fingerprint, and POSTs to `{configuredApiUrl}/api/card-events` with the device bearer token. | `MainActivity.kt`, `CaptureCredentialStore.kt`, backend card-events route |
| `mobile_app/android/app/src/main/kotlin/com/plaidtest/cardsemble/MainActivity.kt` | `MainActivity`, `configureFlutterEngine`, `hasNotificationAccess`, `_postTestNotification` | Implements the Flutter `MethodChannel`, requests notification permission, opens notification-listener settings, and posts the test notification. | `device_capture_repository_impl.dart`, Android manifest |
| `mobile_app/android/app/src/main/kotlin/com/plaidtest/cardsemble/CaptureCredentialStore.kt` | `CaptureCredentialStore.save`, `credentials`, `isConfigured`, `clear` | AES/GCM encryption with Android Keystore for the API URL/device token/device ID. | `MainActivity.kt`, listener service |

### Backend and schema

| File | Important symbols | Responsibility / when to inspect | Inspect together with |
|---|---|---|---|
| `supabase/functions/api/index.ts` | `Deno.serve`, `jsonResponse`, `errorResponse`, `fetchAllRows`, `anyReadyRow`, route blocks | Single API router. Path normalization strips `/functions/v1/<name>`, `/api`, and `api/`; routes are then matched without a leading `/`. It handles public config, card events, household people/members, device tokens, Plaid items/link/sync, Plaid transactions/assignments/splits, credit-account rename/cycle start, statement cycles, reconciliations, and `cron/plaid-sync`. | `_shared/*`, migrations, repository route strings |
| `supabase/functions/_shared/auth.ts` | `authenticateRequest`, `getBearerToken`, `verifySupabaseUser`, `ensureDefaultPerson`, `getHouseholdPerson`, `getDefaultPerson`, `clearDefaultPersonCache`, `addHouseholdMember` | Authenticates Supabase JWT, `CARD_EVENTS_API_TOKEN` test token, or SHA-256 device-token hash. Resolves/creates the household default person. All person lookups are scoped to `(user_id, person_id)`. | `index.ts`, `plaid.ts`, `reconcile.ts` |
 | `supabase/functions/_shared/plaid.ts` | `createPlaidLinkToken`, `exchangePublicToken`, `syncPlaidItemsForUser`, `syncPlaidTransactionPage`, `savePlaidCreditAccounts`, `syncPlaidCreditAccounts`, `runPlaidSync`, `plaidErrorCode` | Plaid REST calls, cursor-based transaction sync, credit-account persistence, legacy access-token migration, and post-sync reconciliation. `syncPlaidLiabilities` and `createLiabilitiesLinkToken` still exist but are unused (`optional_products` no longer includes "liabilities" and the liabilities link-token route is commented out in `index.ts`). Per-item failures are isolated: a Plaid-coded error (e.g. `ITEM_LOGIN_REQUIRED`) becomes a `PlaidItemSyncError` in `item_errors` and the run continues, while a non-Plaid error still propagates. `ITEM_LOGIN_REQUIRED`/`INVALID_ACCESS_TOKEN`/`REAUTH_REQUIRED`/`INVALID_CREDENTIALS` mark the row `plaid_items.status = 'error'`. | `index.ts`, `reconcile.ts`, `plaid_transactions`/`plaid_items` tables |
| `supabase/functions/_shared/reconcile.ts` | `reconcileUserCardEvents`, `refreshWalletAssignments`, `calculateStatementSummaries`, `creditCardDisplayName`, `isGenericCardName`, `fetchUserRows` | Matches captured Wallet events to Plaid transactions by amount/merchant/date (with tip detection), writes reconciliations, refreshes wallet assignments while preserving manual ones, and computes statement-cycle summaries. | `plaid.ts`, `index.ts`, `card_event*`/`transaction_assignments`/`card_statement_summaries` tables |
| `supabase/functions/_shared/merchant.ts` | `PROCESSOR_PREFIXES`, `normalizeMerchantForMatch` | Merchant-name normalization (apostrophe stripping, processor prefixes, card last-4, store numbers) shared by reconciliation. Extracted from the removed CSV matcher to avoid coupling. | `reconcile.ts` |
| `supabase/functions/_shared/supabase.ts` | `createSupabaseAdmin`, `getSupabase`, `supabase` proxy | Service-role Supabase client for the Edge Function. Never expose this client/key to the mobile app. | all backend modules |
| `supabase/functions/_shared/types.ts` | `CardEvent`, `PlaidTransaction`, `PlaidSyncPayload`, `CardEventReconciliation`, etc. | Backend payload/interface definitions. | `index.ts`, `plaid.ts` |
| `card-events-api/card_events.sql` | Base `create table`/policy/trigger statements | Canonical full schema for `card_events`, `profiles`, `device_tokens`, `plaid_transactions`, `plaid_items`, reconciliations, `household_people`, `transaction_assignments`, credit accounts, liabilities, statement summaries, and cycle overrides. Apply this before/alongside migrations on a fresh project. | `supabase/migrations/*`, README |
| `supabase/migrations/20261012210924_add_household_visible_columns.sql` | `household_visible` columns/grants/policies | Adds visibility flags and own-row UPDATE policies. | transactions/card-events visibility code |
| `supabase/migrations/20261012212134_create_household_members_table.sql` | `household_members` table/RLS | Links Supabase users to an owner household and defines owner/member policies. | household membership code |
| `supabase/migrations/20261012213524_add_household_invite_codes.sql` | `generate_invite_code`, `set_owner_invite_code` | Adds unique invite codes for owner rows (`household_id = user_id`). | join-by-invite route |
| `supabase/migrations/20261012220000_add_csv_import_support.sql` | `plaid_transactions.source` | Transaction source tracking column (used by card events and other sources). | `POST /card-events` route |
| `supabase/migrations/20261017000000_fix_transaction_assignment_splits.sql` | `transaction_assignments.amount`, positive constraint, `(transaction_id, person_id)` PK | Defines the single-assignment (`amount NULL`) vs split (`amount > 0`) contract and supports multiple rows per transaction. | split math, assignment routes, cache |

## Feature-to-File Map

### Screens, widgets, navigation, and UI state

- **App shell/navigation:** `mobile_app/lib/app/router/app_router.dart` (`MainTabs`). Tabs are Summary (0), Transactions (1), Events (2), Research (3) in a `PageView`; `_showTransactionsTab` animates to index 1. The People tab was removed; household people management is reachable from the gear menu as "Manage Household", which pushes `PeopleScreen` as a route. There is no `go_router` route table despite the dependency.
- **Settings/capture overlay:** `app_router.dart` (MainTabs now uses per-tab navigators and routes Settings via `CaptureSettingsScreen`) plus `features/device_capture/presentation/capture_settings_screen.dart`. The Summary app-bar gear icon opens a dropdown menu with "Settings", "Manage Household", and "Sign out"; "Settings" opens the `CaptureSettingsScreen` route, "Manage Household" pushes `PeopleScreen`, and "Sign out" signs out via `AuthNotifier`.
- **Research tab:** `mobile_app/lib/features/research/presentation/research_screen.dart` (`ResearchScreen`). Catalog-backed card browser: search field, a results dropdown of matching cards, a selected-cards table, and a "Card Optimizer" button row. The body is a scrollable `LayoutBuilder`/`SingleChildScrollView` so the search dropdown and keyboard never overflow. `showCardOptimizerSettings()` (same file) is the shared "Point Multipliers" sheet: while no points-based card is selected it shows an instruction instead of a default value, and once one is selected it shows the generic `points` input, then one optional `points:<issuer>` override per unique issuer of the selected points cards, then other reward types; cash is never offered. Saving merges into the stored multipliers, so hidden values survive and untouched issuer fields inherit the generic default.
- **Card optimizer screen:** `mobile_app/lib/features/card_optimizer/presentation/card_optimizer_screen.dart` (`CardOptimizerScreen`) shows the best card per rewards category; its app-bar settings icon opens the same multiplier sheet.
- **Card optimizer repository:** `mobile_app/lib/features/card_optimizer/data/card_optimizer_repository.dart` (`CardOptimizerRepository`). Resolves a card's reward type (`rewardTypeFor`), normalizes category labels (`categoryKeyFor`), computes the best card per category (`optimize`), and persists multipliers in `SharedPreferences` under `card_optimizer.type_multipliers.v1` (`loadTypeMultipliers`/`saveTypeMultipliers`). Multiplier precedence is `points:<issuer>` -> `points` -> `card.type` -> 1.0; cash multipliers are always 1.0.
- **Bank/account screen:** `features/summary/presentation/summary_screen.dart` (`_openAccounts`) and `features/accounts/presentation/accounts_screen.dart` (`_linkNewAccount`) both run the shared link flow through `AccountsNotifier.linkAccount()` (Plaid Link -> token exchange -> reload), and both show a success/error SnackBar. On success they show `AccountsNotifier.warning` (if set) instead of `error`, so a link that succeeded with a per-item warning is reported as a success. The Accounts screen also has a "Link Account" FAB.
- **Transactions UI:** `features/transactions/presentation/transactions_screen.dart` and widgets under `presentation/widgets/`.
- **Summary UI:** `features/summary/presentation/summary_screen.dart`.
- **Events UI:** `features/card_events/presentation/card_events_screen.dart`.
- **People UI:** `features/household/presentation/people_screen.dart`; `members_screen.dart` and `invite_screen.dart` exist but are not routed.
- **Auth UI:** `features/auth/presentation/auth_wrapper.dart`, `sign_in_screen.dart`.
- **Shared presentation helpers:** `theme/app_colors.dart`, `core/utils/currency.dart`, `core/utils/date_utils.dart`, `core/utils/color_palette.dart`.

### Transaction queries, filtering, updates, and persistence

- **Query construction:** `TransactionsNotifier._queryFor` builds `TransactionQuery` with page size 100, offset, account filter, and inclusive dates. A null date range falls back to the last 60 days for the server query. The repository serializes `date_from`/`date_to`/`account_id`/`household_visible` in `TransactionQuery.toQueryParameters`.
- **List loading:** `TransactionsNotifier.loadTransactions` / `loadAll`; HTTP route is `GET /api/plaid-transactions` via `TransactionRepositoryImpl.loadTransactions`. The server returns `transactions` + `has_more`.
- **Client-side filtering:** `TransactionsNotifier.filteredTransactions` excludes `isPayment`, applies account/person/date filters, and drops rows without a date. `filteredTotalsByCurrency` sums positive, non-pending, non-payment rows; `filteredTotal` returns the largest currency total, not a cross-currency sum.
- **Filter synchronization:** `setDateRange` reloads the list unless `reloadList: false`; `setAccountFilter`/`setPersonFilter` clear the date range before reloading; `clearAllFilters` clears all three. Summary drilldown calls account, person, then date; `_scheduleListReload` coalesces those into one microtask reload.
- **Assignment:** UI `_runAssignment` -> `TransactionsNotifier.assignTransaction` -> `POST /api/plaid-transactions/{id}/assignment`. Backend deletes existing assignments and inserts a manual assignment (or deletes and reports the default person for unassign), then calls `calculateStatementSummaries`.
- **Splits:** UI `_SplitSection` -> `TransactionsNotifier.loadSplitDraft` -> `LoadTransactionSplitDraft` -> `GET /api/plaid-transactions/{id}/splits`. Save path: slider -> `percentagesToCents` -> `_runSplit` -> `TransactionsNotifier.saveTransactionSplit` -> `SaveTransactionSplit` -> `POST /api/plaid-transactions/{id}/assignment-split`.
- **Visibility:** UI `_runVisibility` -> `TransactionsNotifier.setHouseholdVisible` -> `PATCH /api/plaid-transactions/{id}/household-visible`. The notifier applies an optimistic update and rolls back on failure.
- **Persistence/cache:** `TransactionCache` stores one scoped snapshot key per authenticated user (`cardsemble.cache.v2.transactions.<user>.snapshot`) with four independently timestamped sections (`people`, `accounts`, `transactions`, `summary_transactions`). Writes are queued read-modify-write operations so a partial dataset update cannot refresh unrelated timestamps. `TransactionsNotifier._hydrateFromCache` hydrates fresh sections only; expired sections are retained as a stale fallback if a refresh fails. `_writeCache` writes only changed sections and is fire-and-forget. Legacy `tx_cache_*_v1` keys are unscoped and are purged rather than migrated.

### Household membership and shared visibility

- **People CRUD:** `PeopleScreen` -> `HouseholdNotifier` -> `HouseholdRepositoryImpl` -> `/api/household/people` (`GET`, `POST`, `PATCH`, `DELETE`; update is PATCH by person ID in the repository interface and matching route exists in `index.ts`).
- **Members/invites:** `HouseholdRepositoryImpl.loadMembers/addMember/joinByInviteCode` -> `/api/household/members`, `/api/household/members/join`. `MembersScreen` and `InviteScreen` are not routed; `PeopleScreen` QR scanning is the only in-app caller of `addMember`/`joinByInviteCode`.
- **Household identity:** `household_members` stores `(household_id, user_id, role, invite_code)`; owners have `household_id = user_id`.
- **Current data scoping:** `GET /api/household/people`, `/api/plaid-transactions`, `/api/owed/statement-cycles`, and all shared backend helpers query by `user_id = auth.userId` (or `getHouseholdPerson(userId, personId)`). The inspected RLS policies also compare `auth.uid() = user_id`. There is no inspected join from a member's `household_id` to the owner's transactions/people. See "Verified current-state cautions."
- **Shared-transaction flag:** `plaid_transactions.household_visible` and `card_events.household_visible` default true. The API supports a `household_visible` query parameter, but `TransactionsNotifier` never sets `TransactionQuery.householdVisible`; visibility is currently a per-row flag, not a cross-user data-sharing mechanism.

### Authentication, authorization, and RLS

- **Client sign-in/session:** `AuthRepositoryImpl` uses `SupabaseClient.auth` (`signInWithOAuth(google)`, `signOut`, `onAuthStateChange`). `AuthNotifier` subscribes to the session stream; `AuthWrapper` calls `AuthNotifier.initialize()` after the first frame.
- **OAuth redirect:** `auth_notifier.dart` hardcodes `com.plaidtest.cardsemble://login-callback/`; the same scheme/host is registered in `mobile_app/android/app/src/main/AndroidManifest.xml` and `mobile_app/ios/Runner/Info.plist`.
- **Bearer tokens:** `ApiClient` supplies the Supabase access token. Edge function `authenticateRequest` also accepts `CARD_EVENTS_API_TOKEN` (test; `userId = null`) and SHA-256 device-token hashes stored in `device_tokens` (maps to the owning `user_id`).
 - **Route authorization:** Edge routes returning user data require a non-null `auth.userId`. Device-token creation (`POST /device-tokens`) requires a Supabase session via `verifySupabaseUser`; Plaid link/exchange routes use `authenticateRequest` and therefore accept any user-linked credential (Supabase session or device token) with a non-null `userId`. `cron/plaid-sync` requires `CRON_SECRET`; `plaid-transactions/sync-now` is restricted to `PLAID_USER_ID` (the liabilities link-token route is commented out).
- **RLS/table grants:** Base schema in `card-events-api/card_events.sql` plus `supabase/migrations/*`. Key tables are `user_id`-scoped. `plaid_items` exposes metadata SELECT to the client but not `access_token`; the Edge Function uses the service-role key. `transaction_assignments` grants insert/delete/update to authenticated with own-row policies.

### Plaid connections, synchronization, and duplicate handling

- **Connection list:** `AccountRepositoryImpl.loadPlaidConnections` queries `plaid_items` directly via Supabase (metadata only, excluding `status = 'disconnected'`).
- **Link token:** `AccountsNotifier.createLinkToken` -> `POST /api/plaid/items/link-token?platform=android` -> `createPlaidLinkToken`. `AccountsNotifier.linkAccount` calls it, then opens Plaid Link through `PlaidLinkLauncher`.
- **Token exchange:** `AccountsNotifier.linkAccount` -> `PlaidLinkLauncher.launch` -> Plaid Link -> `POST /api/plaid/items/exchange` (`AccountRepositoryImpl.exchangePlaidPublicToken`) -> backend `exchangePublicToken` (single `/item/public_token/exchange` followed by `/item/get`) which upserts `plaid_items` and immediately runs `syncPlaidItemsForUser`.
- **Manual sync:** `AccountsNotifier.syncConnections` -> `POST /api/plaid/items/sync` -> `syncPlaidItemsForUser`.
 - **Sync pipeline:** For each connected item, `syncPlaidItemsForUser` loops `/transactions/sync` with `transactions_cursor`, upserts added/modified rows, marks removed rows `is_removed = true`, then syncs credit accounts (`/accounts/get`), and runs `reconcileUserCardEvents`, `refreshWalletAssignments`, `calculateStatementSummaries`. The deprecated `/liabilities/get` sync has been removed.
- **Per-item isolation:** The whole per-item body runs inside a `try`/`catch`. Only errors that carry a Plaid `error_code` are treated as per-item failures; they are recorded in `item_errors` (`item_id`, `institution_name`, `error_code`, `message`) and the loop continues. Any other error (database failure, programming error) is rethrown and still fails the whole run, as are the systemic Plaid codes `INVALID_API_KEYS`/`INVALID_INPUT` (a broken integration, not a broken connection). `ITEM_LOGIN_REQUIRED`/`INVALID_ACCESS_TOKEN`/`REAUTH_REQUIRED`/`INVALID_CREDENTIALS` also set that row's `plaid_items.status` to `error` (the only non-`connected`/`disconnected` status the schema allows); a failure to write that status is logged, never thrown. A sync where every item is stale still returns 200 with warnings, but an account with no connected and no stale items still fails with "No Plaid connections are available to sync".
 - **Sync result shape:** `PlaidSyncResult` carries `items_synced` (items that completed), `items_failed` (`item_errors.length`), and `item_errors`. The post-loop reconciliation work (`reconcileUserCardEvents`, `refreshWalletAssignments`, `calculateStatementSummaries`) still runs for the items that did sync.
- **Client-visible warnings:** `AccountRepositoryImpl.syncPlaidConnections` and `exchangePlaidPublicToken` return `Result<PlaidSyncOutcome>`, parsed from the response body's `item_errors`. `AccountsNotifier` surfaces these through a dedicated `warning` channel (separate from `error`), so a link that succeeded but hit a stale item is reported as a success with a warning instead of "Could not link a card".
- **Duplicate handling:** Plaid identity is `transaction_id` (upsert conflict target). Card events are deduplicated server-side by `event_id`. No CSV duplicate detection exists. 
- **Card display names:** `savePlaidCreditAccounts` preserves an existing `display_name` across syncs and only maps known source names when no display name exists. `updateCreditCardDisplayName` writes `plaid_credit_accounts.display_name` directly from the client, then `AccountsNotifier` reloads statement cycles.

### Supabase Edge Functions and database changes

- **Router:** `supabase/functions/api/index.ts` is the only function entry point in the repo. Add routes there and keep the client path strings in sync. Path handling strips `/functions/v1/<name>`, `/api`, and `api/`, so `.../functions/v1/api/api/plaid-transactions` reaches the `plaid-transactions` block.
- **Shared modules:** `_shared/auth.ts`, `_shared/plaid.ts`, `_shared/reconcile.ts`, `_shared/merchant.ts`, `_shared/supabase.ts`, `_shared/types.ts`.
- **Function config:** `supabase/config.toml` sets `[functions.api] verify_jwt = false`; the function performs its own auth. It also contains entries for `functions.card-events`, `functions.cron`, and `functions.test-health`; only `functions/api` exists in the inspected tree, so do not assume those other functions are deployed.
- **Schema workflow:** Base schema is `card-events-api/card_events.sql`; incremental changes are in `supabase/migrations/`. A fresh environment that only applies migrations may lack the base tables. When changing tables/grants/policies, update both the base schema and a migration if the project expects reproducibility.

### Tests and verification

- Unit/widget tests live in `mobile_app/test/`; see "Tests and Commands" below.
- Backend has no Deno test files or test task in the inspected tree. Run `deno check supabase/functions/api/index.ts` for static type-checking, then validate Edge Function behavior against a deployed/local Supabase project with the required secrets.
- Android notification parser tests are under `mobile_app/android/app/src/androidTest/` (both `com.plaidtest.cardsemble` and legacy `com.plaidtest.card_household_app` copies). They are instrumented tests, not run by `flutter test`.

## Architecture and Data Flows

### 1. Startup, configuration, and session

1. `main.dart` runs `CardsembleApp`.
2. `CardsembleApp._initialize` calls `GET {apiBaseUrl}/api/public-config` with `http` (no app auth).
3. The Edge Function `public-config` returns `supabase_url` and `supabase_publishable_key` from function secrets.
4. `ServiceLocator.initialize` calls `AppSupabaseClient.initialize`, creates `ApiClient` with a session-token provider, and registers repositories, notifiers, and split use cases.
5. `MultiProvider` exposes `AuthNotifier`, `HouseholdNotifier`, `TransactionsNotifier`, `CardEventsNotifier`, `AccountsNotifier`, and `DeviceCaptureNotifier`.
6. `AuthWrapper` calls `AuthNotifier.initialize()`; `AuthNotifier` consumes the Supabase `onAuthStateChange` stream. Signed-out users see `SignInScreen`; signed-in users see `MainTabs`.
7. `MainTabs.initState` post-frame calls `DeviceCaptureNotifier.loadPeople`, `checkStatus`, and `TransactionsNotifier.loadAll()` (the single startup ledger fetch).

Data direction: Flutter -> Edge Function `public-config` -> Supabase config; Flutter auth -> Supabase Auth -> `AuthNotifier` -> `AuthWrapper`.

### 2. Shell navigation and shared UI state

1. `MainTabs` builds a `PageView` with Summary, Transactions, Events, Research and a custom `_AnimatedTabBar`.
2. Summary's "Link a card" runs the shared Plaid link flow (`AccountsNotifier.linkAccount()`) instead of navigating away; Summary's gear icon opens a dropdown menu ("Settings", "Manage Household", "Sign out"); "Settings" calls `_openSettings` to show the capture setup overlay, "Manage Household" pushes `PeopleScreen`, "Sign out" signs out.
3. Summary and Transactions both read the same `TransactionsNotifier`. Summary calls `loadSummaryTransactions` for its date range; Transactions calls `loadTransactions` for the list.
4. On first launch, MainTabs checks for unreviewed settings and routes to `CaptureSettingsScreen(firstRun: true)` as a modal route. The screen uses `PopScope` to prevent going back until setup is complete, requiring `isConfigured && hasNotificationAccess` before allowing exit via the Continue button.
5. `didChangeAppLifecycleState(resumed)` rechecks capture status after returning from Android notification settings.

### 3. Ledger load, filtering, and summary drilldown

1. `TransactionsNotifier.loadAll` coalesces concurrent calls, hydrates `TransactionCache`, then loads people and accounts in parallel and calls `loadTransactions(reset: true)`.
2. `loadTransactions` calls `TransactionRepositoryImpl.loadTransactions`, which calls `GET /api/plaid-transactions` with `TransactionQuery`.
3. The Edge Function verifies auth, resolves owned credit accounts, queries `plaid_transactions` with `is_removed = false`, optionally filters by account/date/visibility, joins page-scoped `transaction_assignments`, and enriches each row with account display fields, default-person fallback, and `has_splits`.
4. The notifier stores the list and writes the cache. `filteredTransactions` applies client-side payment/account/person/date filters for the UI.
5. Summary calls `loadSummaryTransactions(range)` (all pages for that date range) and computes `totalsByCurrency`, `totalsByCard`, and `totalsByPersonAndCurrency` locally from positive, posted, non-payment charges.
6. Summary drilldown sets account/person/date filters on the shared notifier and calls `MainTabs._showTransactionsTab`.

### 4. Assignment and split persistence

1. Assignment tap -> `_runAssignment` -> `TransactionsNotifier.assignTransaction` -> repository `POST /assignment`.
2. Backend validates transaction ownership and optional person ownership, deletes prior assignments, inserts one manual assignment with `amount = NULL`, or deletes and reports the default person when `person_id` is null.
3. `calculateStatementSummaries` is invoked after assignment changes.
4. Split expansion -> `_SplitSection` -> `loadSplitDraft` -> `GET /splits`; existing split amounts are converted to percentages and backfilled to all displayed participants.
5. Save -> `_UnifiedSplitSliderBuilder._saveSplit` -> `percentagesToCents` (largest-remainder cent allocation) -> `_runSplit` -> `TransactionsNotifier.saveTransactionSplit` -> `SaveTransactionSplit` validation -> `POST /assignment-split`.
6. Backend validates each person, requires the split total in cents to equal the absolute transaction amount in cents, deletes prior assignments, inserts one `amount > 0` row per split, and recomputes statement summaries.
7. The notifier reloads the ledger and summary after a successful split and rewrites the split-draft cache.

### 5. Summary, card names, and statement cycles

1. `SummaryScreen.initState` sets `_summaryRange` from `TransactionsNotifier.dateRange` (current month by default), loads summary transactions, and loads Plaid connections/statement cycles via `AccountsNotifier`.
2. Card rename -> `_editCardName` -> `AccountsNotifier.updateDisplayName` -> direct Supabase update of `plaid_credit_accounts.display_name` -> `loadStatementCycles`; summary refresh reloads transactions.
3. Statement cycles -> `GET /api/owed/statement-cycles` -> reads `card_statement_summaries`, `plaid_credit_accounts`, `household_people`, and `plaid_liability_sync_state`; returns per-account summaries, `credit_accounts`, `current_total_owed`, `totals_by_currency`, and `total_status`. `plaid_credit_accounts` also exposes `credit_limit`, `current_balance`, and `next_payment_due_date` (populated from Plaid `/accounts/get` syncs; `next_payment_due_date` was previously sourced from `/liabilities/get` but is no longer populated since that product has been deprecated) for per-card and aggregation display.
4. Wallet summary -> `GET /api/wallet/summary` -> reads `plaid_items` (non-disconnected) and `plaid_credit_accounts`; previously returned per-currency `credit_limit_cents`/`balance_cents`/`card_count`, `primary_currency`, `card_count`, and `highest_payment` (largest negative non-pending non-removed transaction in the past 30 days, preferring `transaction_code='payment'`). The `credit_limit_cents` and `balance_cents` fields have been removed (they were sourced from the deprecated `/liabilities/get` product); the route now returns only `card_count` and `highest_cost_transaction` (largest positive non-pending non-removed charge in the past 30 days, excluding explicit `transaction_code='payment'` rows). The Wallet tab computes its card count client-side from the loaded transaction list and derives the highest cost transaction client-side from `TransactionsNotifier.transactions` (via `WalletNotifier.highestCostTransaction`).
4. `calculateStatementSummaries` writes `card_statement_summaries` after Plaid sync and assignment changes. It requires a prior statement date, counts positive posted charges assigned to the primary person, excludes payments/credits/pending, and marks review counts. A total is only returned when all accounts are ready and a single currency is present.

### 6. Plaid connection, sync, and reconciliation

1. `AccountsScreen` loads `plaid_items` directly from Supabase and statement cycles from the Edge Function.
2. "Link Account" -> `AccountsNotifier.linkAccount` -> `POST /api/plaid/items/link-token` -> Plaid `/link/token/create` -> Plaid Link -> `POST /api/plaid/items/exchange` -> `syncPlaidItemsForUser`.
3. Manual sync -> `POST /api/plaid/items/sync` -> `syncPlaidItemsForUser`.
4. For each connected item, transactions are pulled cursor-first, upserted by `transaction_id`, and removals are soft-deleted. Credit accounts and liabilities are refreshed; liability snapshots are upserted by `(user_id, account_id, statement_issue_date)`.
5. A per-item Plaid failure (for example `ITEM_LOGIN_REQUIRED`) does not abort the run: it is recorded in `item_errors`, and the three re-authentication codes also mark the row `plaid_items.status = 'error'`. The response reports `items_synced`, `items_failed`, and `item_errors`, and the client shows the link as successful with a warning. A non-Plaid error still fails the whole request with a 500.
6. After sync, `reconcileUserCardEvents` scores Wallet events against transactions by amount, merchant similarity, and date (with 10–25% tip detection), writing `HIGH`/`MEDIUM`/`AMBIGUOUS`/`REVIEW`/`UNMATCHED`/`PENDING` reconciliations.
7. `refreshWalletAssignments` converts unique HIGH/MEDIUM matches into `assignment_source = 'wallet_event'` rows, preserves manual assignments, and deletes stale wallet assignments. `calculateStatementSummaries` then rebuilds statement summaries.
8. Scheduled sync: `cron/plaid-sync` requires `CRON_SECRET` and uses `PLAID_USER_ID`; it is single-user by design in the inspected code.

### 8. Card-event capture

1. Android `MainActivity` exposes the `com.plaidtest.cardsemble/google_pay_capture` MethodChannel (`configure`, `clear`, `isConfigured`, `deviceId`, `hasNotificationAccess`, `openNotificationAccessSettings`, `sendTestNotification`).
2. CaptureSettingsScreen -> `_autoConfigureStep1` -> `DeviceCaptureNotifier.createDeviceToken` -> `DeviceCaptureRepositoryImpl.createGooglePayDeviceToken` generates a random token, stores only its SHA-256 hash in `device_tokens` via Supabase, then `configureCapture` stores the API URL/token/device ID in `CaptureCredentialStore` (AES/GCM + Android Keystore).
3. `_autoConfigureStep1` currently hardcodes `https://creditcards-beige.vercel.app` as the API URL for the native listener; this is independent of `CARD_EVENTS_API_URL`.
4. `GooglePayNotificationListenerService.onNotificationPosted` filters Google Wallet notifications, parses merchant/amount/currency/card, deduplicates by fingerprint, and POSTs to `{apiUrl}/api/card-events` with `Authorization: Bearer <deviceToken>`.
5. Edge Function `POST card-events` authenticates the token (or Supabase session), resolves the token's `person_id`/`platform`, sets `source`, and upserts `card_events`.
6. The Events tab reads `card_events` and `card_event_reconciliations` directly via Supabase (`limit 200`) and displays source/reconciliation badges.
7. iOS has no notification listener; the documented path is an external iPhone Shortcut posting to the same `/api/card-events` endpoint.

### 9. Household membership (current implementation)

1. `PeopleScreen` loads `/api/household/people`; `GET` ensures a default person exists and returns the caller's `household_people` rows.
2. Create/delete use `/api/household/people`; the repository also exposes `updatePerson` (PATCH) and member methods.
3. `MembersScreen`/`InviteScreen` are not routed. The People QR flow tries `addMember` then `joinByInviteCode`.
4. `household_members` stores owner/member links and invite codes. However, transaction/person/statement queries remain scoped to the authenticated `user_id`; see the caution section.

## Cross-File Dependencies and Invariants

### Shared models and consumers

- `CardTransaction` is consumed by `TransactionRepositoryImpl`, `TransactionsNotifier`, `TransactionCache`, `SummaryScreen`, `TransactionsScreen`, and tests. Adding/renaming a JSON field requires updating `CardTransaction.fromJson/toJson`, the Edge Function projection in `GET /plaid-transactions`, and cache compatibility.
- `TransactionSplit` flows through `split_math.dart`, both split use cases, `TransactionRepositoryImpl`, `TransactionsNotifier`, the split UI, and tests. The persisted contract is `person_id` + positive `amount`.
- `HouseholdPerson` is used by `TransactionsNotifier`, `HouseholdNotifier`, `DeviceCaptureNotifier`, Summary, Transactions, and People. These are three independent people lists; a mutation in one does not automatically refresh the others.
- `StatementAccount`/`StatementCycleSummary` are used by `TransactionRepositoryImpl.loadAccounts`, `TransactionsNotifier`, `AccountsNotifier`, `AccountsScreen`, and Summary. The server returns `credit_accounts` and `accounts`; parsers accept both.

### State ownership and refresh behavior

- `TransactionsNotifier` owns the authoritative ledger list, summary list, date range, account/person filters, people/accounts snapshots, and split-draft cache. `SummaryScreen` keeps its own `_summaryRange` initialized from `notifier.dateRange`.
- `TransactionsScreen._refresh` calls `loadAll()` (ledger/people/accounts only). `SummaryScreen._refresh` calls `notifier.refresh()` (which also reloads the current summary range) and `AccountsNotifier.loadStatementCycles()`.
- `TransactionsNotifier.loadAll` coalesces concurrent calls via `_activeLoadAll`. `loadTransactions` and `loadSummaryTransactions` use generation counters so older responses cannot overwrite newer ones.
- `TransactionsNotifier.loadTransactions` drains all remaining pages in one `while` loop. Although `loadMoreTransactions` and a scroll trigger exist, the initial load normally ends with `_hasMore = false`; do not assume true page-by-page lazy loading without changing this loop.
- `TransactionsNotifier.setHouseholdVisible` is optimistic with rollback. Assignment updates both the ledger and summary copies through `_replaceTransaction`; split save explicitly reloads both.
- `HouseholdNotifier` owns people/members for the People tab; `DeviceCaptureNotifier` owns its own people list for the setup overlay; `AccountsNotifier` owns connections/statement summary. There is no shared invalidation bus, so cross-feature freshness is manual.

### Persistence, identity, and integrity

- Plaid transaction identity is `transaction_id` (primary key). Pending/posted transitions arrive through `/transactions/sync`; removed transactions are soft-deleted with `is_removed = true`, not hard-deleted.
- Card events are deduplicated server-side by `event_id`. Free-user card events are inserted into `plaid_transactions` with `transaction_id = 'evt_<event_id>'` and `source = 'card_event'`.
- `transaction_assignments` has a `(transaction_id, person_id)` primary key. A single/default assignment has `amount IS NULL`; split rows have `amount > 0`. `has_splits` is true when more than one assignment row exists for a transaction.
- Unassigning deletes the assignment and the server returns the household default person; the effective `assignedPersonId` is never the source of truth for "unassigned." Persisted `transaction_assignments.assignment_source` values are `manual` and `wallet_event`; the API also reports synthetic `default` when no row exists.
- `SaveTransactionSplit` enforces at least two unique participants, a 100% sum (tolerance 0.01), positive total, and exact cent totals. `percentagesToCents` uses largest-remainder allocation and omits zero-cent participants; the server independently revalidates the cent sum.
- The UI limits splits to the first four people (`take(4)` in `_SplitSection`/`_runSplit`); the server accepts any number. Changing the UI limit without changing tests/UX may surprise users with larger households.
- Reconciliation statuses are `HIGH`, `MEDIUM`, `AMBIGUOUS`, `REVIEW`, `UNMATCHED`, `PENDING` (no `household_visible`/`ignored`). `refreshWalletAssignments` only auto-assigns HIGH/MEDIUM matches and never overwrites `assignment_source = 'manual'`.
- Statement summaries count positive posted charges only; pending, card payments, refunds, and other credits are excluded. Candidate transactions tied to `AMBIGUOUS`/`REVIEW`/`PENDING` reconciliations are excluded unless a manual assignment exists. A cycle needs a prior statement date; a total is withheld until all accounts are ready and one currency is present.

### Database, RLS, and household isolation

- The transaction/event/account tables carry `user_id`. Base RLS policies and backend queries for those tables scope access to `auth.uid() = user_id` (`profiles` uses `id` instead). `transaction_assignments` and `plaid_credit_accounts` also use own-row policies; `plaid_items` exposes metadata but not the access token.
- `household_members` is a separate membership table. The inspected schema/migrations do **not** add cross-member SELECT policies to `plaid_transactions`, `household_people`, `transaction_assignments`, `card_events`, or statement tables, and the backend queries use `auth.userId` rather than resolving a household owner. Treat "household shared data" as an unresolved requirement, not implemented behavior.
- `household_visible` flags are per-row, default true, and updatable only by the row owner. The client does not pass `household_visible` when loading the ledger, so hidden rows are still returned to the owning user and shared visibility does not expose them to other users.
- `plaid_transactions` and `card_events` are written by the Edge Function using the service-role client, bypassing RLS. Client-side direct writes exist for `device_tokens` and `plaid_credit_accounts.display_name`; keep grants and policies aligned with those paths.
- `card-events-api/card_events.sql` is the full base schema; migrations alter it incrementally. Fresh-project setup must account for this ordering.

### Error handling and concurrency

- Repositories return `Result<T>`; UI/notifiers inspect `isFailure` or `fold`. `ApiClient` converts non-2xx responses to `NetworkException` with the JSON `detail` text; `safe*` methods convert to `FailureResult`.
- `ApiClient` requires a non-empty bearer token and throws `AuthException` otherwise. A missing/expired session therefore surfaces as an auth failure, not an empty data set.
- Do not swallow parse failures in repositories: `loadTransactions` intentionally converts malformed rows into a failure rather than returning partial data.
- `TransactionsNotifier` has two independent generation counters (`_transactionsGeneration`, `_summaryGeneration`) and a microtask reload flag. Preserve them when adding asynchronous loads.
- `loadAll` shares one in-flight future; concurrent tab builds should not trigger duplicate multi-page fetches.

### Verified current-state cautions

The following are observed in the current source and are useful before editing; they are not necessarily intended requirements.

- **Live Plaid linking depends on external setup.** The in-app flow is implemented, but a real session needs the package `com.plaidtest.cardsemble` registered on the Plaid dashboard (the link token requests `android_package_name` `com.plaidtest.cardsemble`) and `PLAID_CLIENT_ID`/`PLAID_SECRET` configured on the Edge Function. The backend exchange now calls `/item/public_token/exchange` exactly once, because Plaid public tokens are single-use.
- **Household sharing is not end-to-end.** Membership/invite code plumbing exists, but transactions/people remain user-scoped. `GET /api/household/members` filters `household_id = auth.userId`. The `POST /api/household/members/join` invite-code lookup was previously broken: it called `.eq("household_id", "user_id")`, which PostgREST interprets as a literal-string comparison against the UUID column (causing a 502 `22P02` cast error, not a 404). This is now fixed: the route queries by `invite_code` alone (UNIQUE, assigned only to owner rows by the `set_owner_invite_code` trigger) and verifies the `household_id = user_id` invariant in JS. The success response now includes `ok: true` so the Flutter `joinByInviteCode` client path (`HouseholdRepositoryImpl.joinByInviteCode`) accepts it without a mobile rebuild. Residual risks: owner rows created before migration `20261012213524` may have NULL `invite_code` (the trigger is BEFORE INSERT only with no backfill), and no code path in the app creates an owner row (`household_id = user_id`) — join will 404 until an owner with an invite code exists in the deployed DB. The `POST /api/household/members/join` route is also the only caller of `addMember`/`joinByInviteCode`; `MembersScreen` and `InviteScreen` are not routed.
- **Household visibility UI is inconsistent.** `CardEventsScreen` treats `reconciliationStatus == 'household_visible'` as visible, but backend reconciliation statuses are HIGH/MEDIUM/AMBIGUOUS/REVIEW/UNMATCHED/PENDING. `CardEventsNotifier.setHouseholdVisible` rebuilds the record without changing any field. Do not assume the visibility toggle reflects server state.
 - **The ledger "load more" path is effectively one full drain.** `loadTransactions` loops until `has_more` is false; `_hasMore` normally becomes false on the first load.
 - **Plaid Liabilities product is deprecated.** `plaid.ts` no longer includes "liabilities" in `optional_products`; `syncPlaidLiabilities` is unused and the `plaid/liabilities/link-token` route in `index.ts` is commented out. `WalletSummary` and `WalletCard` no longer carry `credit_limit_cents`/`balance_cents`/`currentBalanceCents`/`creditLimitCents`/`utilization`; the Wallet tab computes card count and highest cost transaction client-side from `TransactionsNotifier.transactions` and Plaid connection list. `next_payment_due_date` on `plaid_credit_accounts` is no longer populated from `/liabilities/get` (it may be null).
- **Transaction cache is stale-while-revalidate.** Fresh sections hydrate the first frame, but `loadAll` still refreshes from the server. Sections older than 24 hours are not hydrated unless the corresponding remote load fails and the in-memory list is empty (`TransactionsNotifier.isShowingStaleData`). Legacy unscoped `tx_cache_*_v1` keys are intentionally discarded.
- **Capture URL is hardcoded.** `features/device_capture/presentation/capture_settings_screen.dart` `_autoConfigureStep1` configures the native listener with `https://creditcards-beige.vercel.app`, not the `CARD_EVENTS_API_URL`/Edge Function base.
- **Function config references missing functions.** `supabase/config.toml` mentions `functions.card-events`, `functions.cron`, and `functions.test-health`; only `functions/api` exists in the tree. Do not assume those endpoints are deployed.
- **Unused/stale UI files exist.** `device_capture_screen.dart`, `accounts_screen.dart`, `members_screen.dart`, `invite_screen.dart`, and `summary_screen.dart.bak` are not part of the active navigation/build. `accounts_screen.dart` is currently unrouted (only its own widget test instantiates it), although the same `AccountsNotifier` link flow is used in place from Summary.
- **Android package naming is split.** The active Gradle namespace/application ID is `com.plaidtest.cardsemble`; source copies and older docs also use `com.plaidtest.card_household_app`. Register the active ID with Plaid. Release builds currently use the debug signing config.
- **Stale Plaid items are not cleaned up.** A stale item is marked `plaid_items.status = 'error'`, but it is not removed and it stays visible in the app because `loadPlaidConnections` only filters out `status = 'disconnected'`. Items that are already `error` are seeded into `item_errors` on every sync run. A global (non-Plaid) failure that happens after a successful `/api/plaid/items/exchange` still turns that route into a 500, so the client can still report "Could not link a card" for a link whose item was saved.

## Tests and Commands

### Flutter (working directory: `mobile_app`)

| Command | Purpose / status |
|---|---|
| `flutter pub get` | Install dependencies. |
| `flutter analyze` | Static analysis. Verified on 2026-10-21: **No issues found** (one pre-existing info-level `use_build_context_synchronously` in `capture_settings_screen.dart`). |
| `flutter test` | Run all unit/widget tests. Verified on 2026-10-21: **151 tests passed**. |
| `flutter test test/features/transactions/domain/split_math_test.dart` | Run one test file; substitute any path under `test/`. |
| `adb devices` | List Android devices for phone deployment. |
| `flutter run -d <DEVICE_ID>` | Build/run on the selected phone. The API base can be overridden with `--dart-define=CARD_EVENTS_API_URL=...`. |
| `flutter build apk` / `flutter build appbundle` | Release artifacts; inspect signing config first. |

### Test coverage by file

| Test file | Covers |
|---|---|
| `mobile_app/test/core/cache/cached_repository_test.dart` | Cache miss/fresh/expired reads, per-repository TTLs, batched missing keys, partial responses, stale-on-error, corrupt entries, write failures, invalidation, null scope, and late-response scope changes. |
| `mobile_app/test/core/cache/shared_preferences_cache_store_test.dart` | Envelope round-trip, scope/schema/corruption rejection, timestamp preservation, key removal, encoding failure. |
| `mobile_app/test/features/transactions/data/transaction_cache_test.dart` | Snapshot round-trip, per-section timestamps, TTL freshness, corrupt-section isolation, malformed-item invalidation, per-scope keys, concurrent merge, scoped clearing, stale-scope write rejection, legacy purge. |
| `mobile_app/test/features/card_catalog/data/card_catalog_repository_test.dart` | Per-card caching, fresh-hit avoidance, batched missing cards, deselect/reselect reuse, search write-through, custom TTL, partial responses, stale-on-error. |
| `mobile_app/test/features/card_catalog/domain/card_catalog_card_test.dart` | Supplied catalog JSON shape, scalar-tolerant parsing, unknown-key preservation, missing optional fields, stable-id validation. |
| `mobile_app/test/features/transactions/data/transaction_repository_impl_test.dart` | Transaction page parsing/failure behavior, assignment response shapes (default vs nested manual), split parsing/filtering of null/zero/negative/invalid rows, HTTP failure propagation. |
| `mobile_app/test/features/transactions/presentation/transactions_notifier_test.dart` | `loadAll` coalescing, stale-response protection, server-default assignment on unassign, split save reload, split-draft cache hit/rewrite, optimistic visibility rollback, default current-month date filter, fresh/expired cache hydration, session reset, assignment/visibility write-through, late-response scope rejection. |
| `mobile_app/test/features/transactions/presentation/transactions_screen_test.dart` | Long assignee-name layout/overflow, 3- and 4-participant horizontal split layout, unified slider presence, current-month date chip. |
| `mobile_app/test/features/transactions/domain/split_math_test.dart` | Equal split remainders, guideline snapping, boundary movement/minimums, cent-exact allocation and no negative/zero shares, serialized split payload, normalization/backfill. |
| `mobile_app/test/features/household/presentation/people_screen_test.dart` | People screen add buttons and QR scanner dialog behavior. |
| `mobile_app/test/features/research/presentation/research_screen_test.dart` | Search results plus an open keyboard do not overflow the Research tab layout. |
| `mobile_app/test/features/research/presentation/multiplier_sheet_test.dart` | Point Multipliers sheet: an instruction replaces the points input until a points card is selected, issuer inputs are sorted, stored values prefill, saving keeps hidden stored keys, untouched issuer fields inherit the default, invalid values are rejected. |
| `mobile_app/test/features/card_optimizer/data/card_optimizer_repository_test.dart` | Reward-type resolution, category normalization, best-card-per-category ranking, cash multipliers ignored, issuer multiplier precedence over the generic points multiplier, multiplier persistence roundtrip. |
| `mobile_app/test/features/accounts/presentation/accounts_notifier_test.dart` | `linkAccount` success path (link token, Plaid Link, exchange, reloads, `lastLinkedInstitutionName`), link-token failure, user exit, exchange failure, the post-exchange reload-failure warning, a successful link with a per-item re-authentication warning, and `syncConnections` warning/no-warning results. |
| `mobile_app/test/features/accounts/data/plaid_link_launcher_impl_test.dart` | Plaid Link success/exit mapping and platform-failure handling using a fake `PlaidPlatformInterface`. |
| `mobile_app/test/features/accounts/domain/plaid_sync_outcome_test.dart` | `item_errors` payload parsing, missing/non-list `item_errors`, malformed-row skipping, and `needsReauthentication` codes. |
| `mobile_app/test/features/accounts/presentation/accounts_screen_test.dart` | Accounts screen link flow SnackBars (success, failure, post-link reload warning, and a successful link with a re-authentication warning). |

### Android instrumented tests

- Files: `mobile_app/android/app/src/androidTest/kotlin/com/plaidtest/cardsemble/GooglePayNotificationParserTest.kt` and a legacy `com.plaidtest.card_household_app` copy.
- They exercise amount/currency/card parsing for USD/EUR/Mastercard/Visa-style notifications.
- They are **not** run by `flutter test`. The inspected `mobile_app/android/app/build.gradle.kts` does not declare AndroidX test dependencies, so treat the Gradle connected-test command as unverified/not configured; do not claim those tests pass without running them on a device.

### Backend verification

- `deno check supabase/functions/api/index.ts` — Type-check the Edge Function and all transitively imported shared modules. Verified: **0 errors**.
- No Deno test files exist under `supabase/functions/_shared/`; backend verification is via type-checking and deployed/local Supabase runtime checks.
- `supabase/config.toml` only provides local function configuration; deployment/secrets (`PLAID_CLIENT_ID`, `PLAID_SECRET`, `PLAID_USER_ID`, `PLAID_ACCESS_TOKEN`, `PLAID_ENV`, `CRON_SECRET`, `CARD_EVENTS_API_TOKEN`, Supabase service-role/anon keys) are environment concerns, not committed configuration.
- For backend changes, inspect `supabase/functions/api/index.ts` route blocks and the relevant `_shared` module, then verify against a deployed/local Supabase project.

## Best Starting Points for Common Changes

- **Transaction tile, filters, assignment, split UI:** `transactions_screen.dart` + `transactions_notifier.dart` + `transaction.dart`; run `transactions_screen_test.dart`, `transactions_notifier_test.dart`, `split_math_test.dart`.
- **Ledger API behavior:** `transaction_repository_impl.dart`, `supabase/functions/api/index.ts`, `_shared/plaid.ts`, `_shared/reconcile.ts`; update `transaction_repository_impl_test.dart` for wire-format changes.
- **Summary totals/date range/drilldown:** `summary_screen.dart` + `transactions_notifier.dart`; remember the shared date range and the current-month default.
- **Household people/members/invites:** `people_screen.dart` / `household_notifier.dart` / `household_repository_impl.dart` + `index.ts` household routes + `household_members` migrations/RLS.
- **Plaid linking/sync/statements:** `accounts_screen.dart`, `accounts_notifier.dart`, `account_repository_impl.dart`, `plaid_link_launcher.dart`, `plaid_link_launcher_impl.dart`, `_shared/plaid.ts`, `_shared/reconcile.ts`, `index.ts` routes, and the Plaid-related migrations.
- **Android capture:** `app_router.dart` setup overlay, `device_capture_notifier.dart`, `device_capture_repository_impl.dart`, `MainActivity.kt`, `GooglePayNotificationListenerService.kt`, `CaptureCredentialStore.kt`, and the `card-events` backend route.
- **Auth/session:** `auth_wrapper.dart`, `auth_notifier.dart`, `auth_repository_impl.dart`, `app.dart`, Android manifest/iOS `Info.plist` redirect configuration.
- **Shared caching or card catalog:** `core/cache/cache_store.dart`, `core/cache/cached_repository.dart`, `features/transactions/data/transaction_cache.dart`, `features/card_catalog/`; run the cache, transaction-cache, notifier, and catalog tests. The card catalog has no backend/source yet, so keep it out of DI until `CardCatalogSource` is implemented.

## Maintaining This Guide

- When a code change materially affects documented file responsibilities, important symbols, architecture, data flows, dependencies, or verification commands, update the relevant sections of this guide in the same task.
- Update only affected sections. Do not rewrite the guide or document routine implementation details that do not improve future code navigation.
- Verify documented paths, symbols, and behavior against the resulting code. Remove obsolete references and correct outdated descriptions.
- The implementing agent is responsible for necessary updates. Read-only agents should report inaccuracies or missing updates without editing files.
- If no documented information changes, leave this guide untouched.