-- Fix: Ensure device_tokens has proper table-level grants for authenticated role.
-- The original migration used column-level grants only, which may have failed
-- if the person_id column was not present on the remote database at apply time,
-- leaving the authenticated role with no INSERT permission at all.

-- Ensure the person_id column exists (added by card_events.sql, but may be missing on remote)
alter table public.device_tokens
    add column if not exists person_id uuid
    references public.household_people(person_id) on delete set null;

-- Grant table-level permissions (covers all columns, including defaults)
grant select, insert, update on table public.device_tokens to authenticated;

-- Ensure RLS policies exist
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
