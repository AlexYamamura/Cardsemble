# Cardsemble mobile app

This Flutter app is the mobile client for the existing FastAPI/Supabase service.
It provides a selectable-date-range household spending summary with card and
person breakdowns, a full synced Plaid transaction ledger, and captured card
events. A signed-in household member can manually assign transactions or
return them to the household default. Household members can also be added in
the app. Statement balances are shown separately from transaction spending.
Plaid's card names may be generic; use the edit icon beside a card in the
summary to save a household display name. The original Plaid names and the
household label are stored separately.
Open Settings from the top-right action to link more banks/cards with Plaid
Link. Each selected institution account is stored as its own Plaid Item and
syncs transactions automatically. The app never receives the Plaid access
token. Plaid's optional Liabilities product supplies statement data where
supported; transaction syncing remains available when it is not.
Capture configuration appears in Settings and is shown once on first launch.

## Run

From this directory:

```powershell
flutter pub get
flutter run --dart-define=CARD_EVENTS_API_URL=https://YOUR-PROJECT.supabase.co/functions/v1/api
```

`CARD_EVENTS_API_URL` points to the Supabase Edge Function that serves the API.
Simple CRUD operations (household members, card events, device tokens, credit card
display names, Plaid connections) go directly through the Supabase client. Plaid
operations, card-event creation (device-token auth), statement-cycle calculations,
and reconciliation are handled by the edge function.

The app uses the existing Google sign-in provider. Add this redirect URL to the
Supabase project's Authentication URL allow list:

```text
com.plaidtest.cardsemble://login-callback/
```

The matching Android intent filter and iOS URL scheme are already registered
in the platform projects. Google OAuth provider credentials must also be enabled
in Supabase.

For Android Plaid Link, register the package ID
`com.plaidtest.cardsemble` in Plaid Dashboard under **Team Settings →
API → Allowed Android package names** before testing a live Link session.
The Plaid integration requests Transactions and optional Liabilities access.
Plaid Link shows the institutions available for the Plaid environment and lets
you select the account(s) to share. The AAA Daily Advantage card can be linked
there if its issuer is available through your Plaid production account.

The Plaid Link Flutter SDK requires iOS 14 or later. Register the required
OAuth redirect configuration in the Plaid Dashboard for iOS institutions that
use OAuth.

## Capture platform differences

- iOS: continue using the iPhone Shortcut to submit card events to the API.
  iOS does not allow an app to inspect notifications from other apps.
- Android: the Google Wallet / Google Pay capture integration listens only to
  notifications from Google Wallet's Android package. Setup creates a
  person-specific device key and asks the user to grant Android notification
  access. Matching transaction alerts containing a merchant and a supported
  currency amount are submitted automatically. Other apps' notifications are
  ignored. Disconnecting revokes the server-side key and removes its encrypted
  local copy.

The notification-listener permission is broad at the Android OS level even
though this listener filters to Google Wallet before reading notification
content. Grant it only if comfortable with that permission. Parsing is based on
the provided Google Pay alert example; Google may change notification formats.
Samsung Pay is not included.

After adding the Android capture feature, apply the updated
`card_events.sql` to Supabase so `device_tokens.platform` is available.
Existing device keys default to `ios_shortcut`.

Supabase Edge Functions replace the previously Vercel-deployed FastAPI app.
Plaid Link, public-token exchange, scheduled sync, and card-event creation
(device-token auth) run as edge functions with Plaid credentials stored as
Supabase Function Secrets. The daily Plaid sync is scheduled via `pg_cron`
calling the `cron/plaid-sync` route on the `api` edge function. The mobile app
makes direct Supabase calls for simple CRUD where possible, falling back to
the edge function for Plaid and statement-cycle operations.
