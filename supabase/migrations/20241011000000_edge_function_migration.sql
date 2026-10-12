-- Migration: Enable row-level write access for authenticated users on tables
-- that the mobile app now writes to directly (instead of through the API).
-- Before this migration, most tables only granted SELECT to authenticated users.
-- The service role key was required for INSERT/UPDATE/DELETE.

-- card_events: allow authenticated users to insert their own events
-- (person_id, device_token_id, and source are set by the edge function
-- for device-token auth; the mobile app sets source=authenticated_api)
grant insert (event_id, occurred_at, amount, currency, merchant, card_label, payment_label, person_id, device_token_id, source) on table public.card_events to authenticated;
grant update (person_id) on table public.card_events to authenticated;

drop policy if exists "Users can insert their own card events" on public.card_events;
create policy "Users can insert their own card events"
    on public.card_events
    for insert
    to authenticated
    with check (auth.uid() = user_id);

drop policy if exists "Users can update their own card events" on public.card_events;
create policy "Users can update their own card events"
    on public.card_events
    for update
    to authenticated
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- household_people: allow authenticated users to create household members
grant insert (user_id, display_name, is_default) on table public.household_people to authenticated;
grant update (display_name, person_id) on table public.household_people to authenticated;

drop policy if exists "Users can insert their own household people" on public.household_people;
create policy "Users can insert their own household people"
    on public.household_people
    for insert
    to authenticated
    with check (auth.uid() = user_id);

drop policy if exists "Users can update their own household people" on public.household_people;
create policy "Users can update their own household people"
    on public.household_people
    for update
    to authenticated
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- device_tokens: allow authenticated users to create and revoke device tokens
-- Note: the client generates the token, hashes it with SHA-256, and inserts only the hash
grant insert (user_id, person_id, device_label, platform, token_hash) on table public.device_tokens to authenticated;
grant update (person_id, revoked_at, last_used_at) on table public.device_tokens to authenticated;

drop policy if exists "Users can create their own device tokens" on public.device_tokens;
create policy "Users can create their own device tokens"
    on public.device_tokens
    for insert
    to authenticated
    with check (auth.uid() = user_id);

drop policy if exists "Users can read their own device tokens" on public.device_tokens;
create policy "Users can read their own device tokens"
    on public.device_tokens
    for select
    to authenticated
    using (auth.uid() = user_id);

drop policy if exists "Users can update their own device tokens" on public.device_tokens;
create policy "Users can update their own device tokens"
    on public.device_tokens
    for update
    to authenticated
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- plaid_transactions: allow authenticated users to insert/update their transactions
-- (used by cloud_store.py and the client for Plaid sync results)
grant insert (transaction_id, user_id, account_id, amount, iso_currency_code, date, authorized_date, datetime, authorized_datetime, name, original_description, merchant_name, merchant_entity_id, website, merchant_category_code, payment_channel, location_address, location_city, location_region, location_postal_code, location_country, location_lat, location_lon, location_store_number, personal_finance_category_primary, personal_finance_category_detailed, personal_finance_category_confidence, transaction_type, transaction_code, pending, pending_transaction_id, counterparties, payment_meta, is_removed, synced_at) on table public.plaid_transactions to authenticated;
grant update (is_removed, synced_at) on table public.plaid_transactions to authenticated;

drop policy if exists "Users can insert their own Plaid transactions" on public.plaid_transactions;
create policy "Users can insert their own Plaid transactions"
    on public.plaid_transactions
    for insert
    to authenticated
    with check (auth.uid() = user_id);

drop policy if exists "Users can update their own Plaid transactions" on public.plaid_transactions;
create policy "Users can update their own Plaid transactions"
    on public.plaid_transactions
    for update
    to authenticated
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- card_event_reconciliations: allow authenticated users to upsert reconciliations
grant insert (event_id, user_id, candidate_transaction_id, status, event_amount, plaid_amount, amount_difference, details, updated_at) on table public.card_event_reconciliations to authenticated;
grant update (candidate_transaction_id, status, plaid_amount, amount_difference, details, updated_at) on table public.card_event_reconciliations to authenticated;

drop policy if exists "Users can insert their own reconciliations" on public.card_event_reconciliations;
create policy "Users can insert their own reconciliations"
    on public.card_event_reconciliations
    for insert
    to authenticated
    with check (auth.uid() = user_id);

drop policy if exists "Users can update their own reconciliations" on public.card_event_reconciliations;
create policy "Users can update their own reconciliations"
    on public.card_event_reconciliations
    for update
    to authenticated
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- transaction_assignments: allow authenticated users to upsert/delete assignments
grant insert (transaction_id, user_id, person_id, assignment_source, event_id, updated_at) on table public.transaction_assignments to authenticated;
grant delete on table public.transaction_assignments to authenticated;

drop policy if exists "Users can insert their own transaction assignments" on public.transaction_assignments;
create policy "Users can insert their own transaction assignments"
    on public.transaction_assignments
    for insert
    to authenticated
    with check (auth.uid() = user_id);

drop policy if exists "Users can update their own transaction assignments" on public.transaction_assignments;
create policy "Users can update their own transaction assignments"
    on public.transaction_assignments
    for update
    to authenticated
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

drop policy if exists "Users can delete their own transaction assignments" on public.transaction_assignments;
create policy "Users can delete their own transaction assignments"
    on public.transaction_assignments
    for delete
    to authenticated
    using (auth.uid() = user_id);

-- plaid_credit_accounts: allow authenticated users to update their own display names
grant update (display_name) on table public.plaid_credit_accounts to authenticated;

drop policy if exists "Users can update their own credit accounts" on public.plaid_credit_accounts;
create policy "Users can update their own credit accounts"
    on public.plaid_credit_accounts
    for update
    to authenticated
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- card_cycle_start_overrides: allow authenticated users to insert cycle overrides
grant insert (user_id, account_id, statement_issue_date, cycle_start_date, updated_at) on table public.card_cycle_start_overrides to authenticated;

drop policy if exists "Users can insert their own cycle start overrides" on public.card_cycle_start_overrides;
create policy "Users can insert their own cycle start overrides"
    on public.card_cycle_start_overrides
    for insert
    to authenticated
    with check (auth.uid() = user_id);

-- Scheduled sync via pg_cron
-- This cron job runs daily at 12:00 UTC and calls the api edge function's
-- cron/plaid-sync route. The CRON_SECRET must be set as a function secret.
--
-- After deploying, add this cron job:
--   supabase db reset  (if using local)
--   Or run in the SQL editor:
--
-- SELECT cron.schedule(
--   'daily-plaid-sync',
--   '0 12 * * *',
--   $$
--   SELECT
--     net.http_post(
--       'https://YOUR-PROJECT.supabase.co/functions/v1/api',
--       json_build_object(
--         'path', 'cron/plaid-sync',
--         'method', 'GET',
--           'headers', json_build_object(
--             'Authorization', concat('Bearer ', current_setting('app.settings.cron_secret'))
--           )
--       ),
--       '1'::text,
--       current_setting('app.settings.cron_secret')
--     )
--   $$
-- );
--
-- Note: pg_cron must be enabled. In Supabase, it is available in the
-- dedicated database instance. Enable it with:
--   CREATE EXTENSION IF NOT EXISTS cron;
