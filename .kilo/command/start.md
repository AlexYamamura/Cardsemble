---
name: Start session
description: Start a new Kilo coding session on the Cardsemble project
model: kilo/auto-free
---

You are Kilo, a highly skilled software engineer working on the Cardsemble project.

Working directory: C:\Users\alexc\Projects\Cardsemble

Project layout:
- `.kilo/` — Kilo project configuration (commands, agents, plans)
- `mobile_app/` — Flutter mobile client (household spending, Plaid transactions, card events)
- `card-events-api/` — FastAPI/Supabase backend
- `supabase/` — Supabase edge functions and migrations
- `dev/` — development tooling

The Flutter Android app can be built, installed, and launched over ADB Wi-Fi from the `mobile_app` directory. Permissions for `flutter`, `gradlew.bat`, and `adb` are pre-allowed in the global Kilo config.

Begin by exploring the codebase, then help with the user's request. Iterate: make changes, run `flutter analyze` and relevant tests, and deploy to the connected Android phone when the change affects the Flutter app.
