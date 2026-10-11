# Household statement-cycle workflow

## Setup

1. Run the full `card_events.sql` in the Supabase SQL Editor. It is safe to rerun
   and creates or updates the household, Plaid connection, assignment,
   liability snapshot, and statement summary tables used by the API.
2. Sign in at `/login`. The account creator is initialized as the household's
   default person. Add other people by name.
3. Assign the existing iPhone Shortcut key to the person whose Wallet events
   that phone reports, or create a new key with that person selected. Events
   received after this assignment inherit the device's person. Older events
   that predate the device/person mapping remain unassigned for review.
4. In Settings, choose **Link another card** and complete Plaid Link. Plaid
   saves a separate Item for each institution and selected accounts. Each Item's
   transactions cursor and server-only access token are retained in
   `plaid_items`; card account metadata is stored separately in
   `plaid_credit_accounts`. Link requests transactions and asks for optional
   liabilities consent so statement data can be included where supported.
5. For the first cycle, enter the prior statement close date shown on the
   previous bill if Plaid has only returned the latest statement date. This
   date is stored as a user-entered cycle boundary, not represented as a
   historical Plaid statement snapshot.

## How totals are calculated

- Plaid's statement issue dates define a card cycle when two are available.
  For the initial cycle only, the previous close date may be entered from the
  card statement. Posted transactions after that date through the latest issue
  date are considered.
- A confidently matched Wallet event assigns a transaction to the person
  linked to that event's device key. A manual transaction assignment takes
  precedence.
- Anything with no explicit or Wallet assignment falls back to the default
  household person (the account creator).
- Only positive posted transactions in the credit-card account are counted as
  charges. Pending transactions, card payments, refunds, and other credits do
  not reduce either person's share.
- Confidently matched Wallet events assign a charge to that phone's person.
  Manually assigned charges use the selected person, and all other charges
  fall back to the default household person.
- Unmatched, pending, ambiguous, and amount-changed Wallet events appear as
  review items. Candidate transactions needing review are not counted until
  manually assigned.
- A cycle is not considered complete until two distinct statement issue dates
  are available for every connected credit-card account. The app will not sum
  unlike currencies into a single total.

Plaid Liabilities coverage varies by card issuer. If the issuer does not return
statement data, transaction syncing continues, but the app cannot produce a
statement-cycle total for that card from Plaid alone. The account's monthly
summary is available from `GET /api/owed/statement-cycles`.

Plaid's `name` and `official_name` are saved as source metadata, but some issuers
return generic labels (for example, `CREDIT CARD` and `Ultimate Rewards`) rather
than the specific card product. Known source labels are normalized through the
card-name mapper (currently `Ultimate Rewards` to `Chase Freedom Unlimited`);
the summary also lets a household set a separate display name when the source
label is unknown or ambiguous. Explicit household labels are retained through
later Plaid syncs and do not replace the original Plaid values.

The total is a split of charges by person, not the card's payment due.
Statement balance, minimum payment, and due date are retained as reference
data; existing unpaid balances and payments are not allocated to household
members by this first version. Push notifications and email delivery are not
configured yet.

The scheduled sync processes every connected Plaid Item belonging to the
configured `PLAID_USER_ID`. Existing deployments using `PLAID_ACCESS_TOKEN`
are migrated into `plaid_items` on the next sync. Separate household logins
still require a multi-user scheduled-sync configuration.

Before testing Android Link, add the app ID
`com.plaidtest.card_household_app` under Plaid Dashboard **Team Settings → API →
Allowed Android package names**. For iOS, register the app's OAuth redirect
configuration as required by the institution-specific Plaid Link flow.
