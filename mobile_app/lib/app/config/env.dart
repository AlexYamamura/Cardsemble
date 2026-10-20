const String supabaseBaseUrl = String.fromEnvironment(
  'CARD_EVENTS_API_URL',
  defaultValue: 'https://ebawvkiabuhcyvyzegfn.supabase.co/functions/v1/api',
);

const String oauthRedirectUrl = 'com.plaidtest.cardsemble://login-callback/';

const String settingsReviewedKey = 'capture_settings_reviewed';