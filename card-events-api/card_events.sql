create table if not exists public.card_events (
    event_id text primary key default (gen_random_uuid())::text,
    user_id uuid references auth.users(id) on delete set null,
    occurred_at timestamptz not null,
    amount numeric(12, 2) not null check (amount > 0),
    currency text not null check (char_length(currency) = 3),
    merchant text not null,
    card_label text not null,
    payment_label text not null default 'uncategorized',
    source text not null,
    received_at timestamptz not null default now()
);

alter table public.card_events
    alter column event_id set default (gen_random_uuid())::text;

alter table public.card_events
    add column if not exists user_id uuid references auth.users(id) on delete set null;

alter table public.card_events
    add column if not exists payment_label text not null default 'uncategorized';

alter table public.card_events enable row level security;

drop policy if exists "Users can read their own card events"
    on public.card_events;
create policy "Users can read their own card events"
    on public.card_events
    for select
    to authenticated
    using (auth.uid() = user_id);

revoke all on public.card_events from anon, authenticated;
grant select on public.card_events to authenticated;

create table if not exists public.profiles (
    id uuid primary key references auth.users(id) on delete cascade,
    username text unique,
    display_name text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

insert into public.profiles (id, display_name)
select
    id,
    coalesce(
        nullif(raw_user_meta_data ->> 'full_name', ''),
        nullif(raw_user_meta_data ->> 'name', '')
    )
from auth.users
on conflict (id) do nothing;

drop policy if exists "Users can read their own profile"
    on public.profiles;
create policy "Users can read their own profile"
    on public.profiles
    for select
    to authenticated
    using (auth.uid() = id);

drop policy if exists "Users can update their own profile"
    on public.profiles;
create policy "Users can update their own profile"
    on public.profiles
    for update
    to authenticated
    using (auth.uid() = id)
    with check (auth.uid() = id);

revoke all on public.profiles from anon, authenticated;
grant select on public.profiles to authenticated;
grant update (username, display_name, updated_at)
    on public.profiles to authenticated;

create or replace function public.create_profile_for_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    insert into public.profiles (id, display_name)
    values (
        new.id,
        coalesce(
            nullif(new.raw_user_meta_data ->> 'full_name', ''),
            nullif(new.raw_user_meta_data ->> 'name', '')
        )
    )
    on conflict (id) do nothing;

    return new;
end;
$$;

drop trigger if exists on_auth_user_created_profile on auth.users;
create trigger on_auth_user_created_profile
    after insert on auth.users
    for each row execute procedure public.create_profile_for_new_user();

create table if not exists public.device_tokens (
    id uuid primary key default gen_random_uuid(),
    token_hash text not null unique,
    user_id uuid not null references auth.users(id) on delete cascade,
    device_label text not null,
    created_at timestamptz not null default now(),
    revoked_at timestamptz,
    last_used_at timestamptz
);

alter table public.device_tokens
    add column if not exists platform text not null default 'ios_shortcut'
    check (platform in ('ios_shortcut', 'android_google_pay'));

alter table public.device_tokens enable row level security;
revoke all on public.device_tokens from anon, authenticated;

create table if not exists public.plaid_transactions (
    transaction_id text primary key,
    user_id uuid not null references auth.users(id) on delete cascade,
    account_id text,
    amount numeric(14, 2) not null,
    iso_currency_code text,
    date date,
    authorized_date date,
    datetime timestamptz,
    authorized_datetime timestamptz,
    name text,
    original_description text,
    merchant_name text,
    merchant_entity_id text,
    website text,
    merchant_category_code text,
    payment_channel text,
    location_address text,
    location_city text,
    location_region text,
    location_postal_code text,
    location_country text,
    location_lat numeric,
    location_lon numeric,
    location_store_number text,
    personal_finance_category_primary text,
    personal_finance_category_detailed text,
    personal_finance_category_confidence text,
    transaction_type text,
    transaction_code text,
    pending boolean not null default false,
    pending_transaction_id text,
    counterparties jsonb,
    payment_meta jsonb,
    is_removed boolean not null default false,
    synced_at timestamptz not null default now()
);

create index if not exists plaid_transactions_user_date_idx
    on public.plaid_transactions (user_id, date desc);

alter table public.plaid_transactions enable row level security;
drop policy if exists "Users can read their own Plaid transactions"
    on public.plaid_transactions;
create policy "Users can read their own Plaid transactions"
    on public.plaid_transactions
    for select
    to authenticated
    using (auth.uid() = user_id);
revoke all on public.plaid_transactions from anon, authenticated;
grant select on public.plaid_transactions to authenticated;

create table if not exists public.plaid_sync_state (
    user_id uuid primary key references auth.users(id) on delete cascade,
    cursor text,
    updated_at timestamptz not null default now()
);

alter table public.plaid_sync_state enable row level security;
revoke all on public.plaid_sync_state from anon, authenticated;

create table if not exists public.plaid_items (
    item_id text primary key,
    user_id uuid not null references auth.users(id) on delete cascade,
    access_token text not null,
    institution_id text,
    institution_name text not null,
    transactions_cursor text,
    status text not null default 'connected'
        check (status in ('connected', 'error', 'disconnected')),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (user_id, item_id)
);

create index if not exists plaid_items_user_status_idx
    on public.plaid_items (user_id, status);

alter table public.plaid_items enable row level security;
revoke all on public.plaid_items from anon, authenticated;

create table if not exists public.card_event_reconciliations (
    event_id text primary key references public.card_events(event_id) on delete cascade,
    user_id uuid not null references auth.users(id) on delete cascade,
    candidate_transaction_id text references public.plaid_transactions(transaction_id) on delete set null,
    status text not null check (
        status in ('HIGH', 'MEDIUM', 'AMBIGUOUS', 'REVIEW', 'UNMATCHED', 'PENDING')
    ),
    event_amount numeric(12, 2) not null check (event_amount > 0),
    plaid_amount numeric(14, 2),
    amount_difference numeric(14, 2),
    details jsonb not null default '{}'::jsonb,
    updated_at timestamptz not null default now()
);

create index if not exists card_event_reconciliations_user_status_idx
    on public.card_event_reconciliations (user_id, status);

alter table public.card_event_reconciliations enable row level security;
drop policy if exists "Users can read their own card event reconciliations"
    on public.card_event_reconciliations;
create policy "Users can read their own card event reconciliations"
    on public.card_event_reconciliations
    for select
    to authenticated
    using (auth.uid() = user_id);
revoke all on public.card_event_reconciliations from anon, authenticated;
grant select on public.card_event_reconciliations to authenticated;

create table if not exists public.household_people (
    person_id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    display_name text not null,
    is_default boolean not null default false,
    created_at timestamptz not null default now(),
    unique (user_id, person_id)
);

create unique index if not exists household_people_one_default_idx
    on public.household_people (user_id)
    where is_default;

insert into public.household_people (user_id, display_name, is_default)
select
    profile.id,
    coalesce(nullif(profile.display_name, ''), 'Primary member'),
    true
from public.profiles as profile
where not exists (
    select 1
    from public.household_people as person
    where person.user_id = profile.id
      and person.is_default
);

create or replace function public.create_default_household_person()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    insert into public.household_people (user_id, display_name, is_default)
    values (
        new.id,
        coalesce(nullif(new.display_name, ''), 'Primary member'),
        true
    )
    on conflict (user_id) where is_default do nothing;

    return new;
end;
$$;

drop trigger if exists on_profile_created_household_person
    on public.profiles;
create trigger on_profile_created_household_person
    after insert on public.profiles
    for each row execute procedure public.create_default_household_person();

alter table public.household_people enable row level security;
drop policy if exists "Users can read their own household people"
    on public.household_people;
create policy "Users can read their own household people"
    on public.household_people
    for select
    to authenticated
    using (auth.uid() = user_id);
revoke all on public.household_people from anon, authenticated;
grant select on public.household_people to authenticated;

alter table public.card_events
    add column if not exists person_id uuid
    references public.household_people(person_id) on delete set null;

alter table public.device_tokens
    add column if not exists person_id uuid
    references public.household_people(person_id) on delete set null;

alter table public.card_events
    add column if not exists device_token_id uuid
    references public.device_tokens(id) on delete set null;

create table if not exists public.transaction_assignments (
    transaction_id text not null
        references public.plaid_transactions(transaction_id) on delete cascade,
    user_id uuid not null references auth.users(id) on delete cascade,
    person_id uuid not null
        references public.household_people(person_id) on delete cascade,
    amount numeric(12, 2) check (amount is null or amount > 0),
    assignment_source text not null
        check (assignment_source in ('manual', 'wallet_event')),
    event_id text references public.card_events(event_id) on delete set null,
    updated_at timestamptz not null default now(),
    primary key (transaction_id, person_id)
);

create index if not exists transaction_assignments_user_person_idx
    on public.transaction_assignments (user_id, person_id);

alter table public.transaction_assignments enable row level security;
drop policy if exists "Users can read their own transaction assignments"
    on public.transaction_assignments;
create policy "Users can read their own transaction assignments"
    on public.transaction_assignments
    for select
    to authenticated
    using (auth.uid() = user_id);
revoke all on public.transaction_assignments from anon, authenticated;
grant select on public.transaction_assignments to authenticated;

create table if not exists public.plaid_credit_accounts (
    account_id text primary key,
    user_id uuid not null references auth.users(id) on delete cascade,
    name text not null,
    official_name text,
    display_name text,
    mask text,
    account_type text,
    item_id text,
    institution_name text,
    subtype text,
    iso_currency_code text,
    credit_limit numeric(14, 2),
    current_balance numeric(14, 2),
    updated_at timestamptz not null default now(),
    unique (user_id, account_id)
);

alter table public.plaid_credit_accounts
    add column if not exists display_name text;
alter table public.plaid_credit_accounts
    add column if not exists account_type text;
alter table public.plaid_credit_accounts
    add column if not exists item_id text;
alter table public.plaid_credit_accounts
    add column if not exists institution_name text;
alter table public.plaid_credit_accounts
    add column if not exists credit_limit numeric(14, 2);
alter table public.plaid_credit_accounts
    add column if not exists current_balance numeric(14, 2);
update public.plaid_credit_accounts
set account_type = 'credit'
where account_type is null;
update public.plaid_credit_accounts
set display_name = 'Chase Freedom Unlimited'
where display_name is null
  and (
      regexp_replace(lower(coalesce(official_name, '')), '[^a-z0-9]', '', 'g')
          = 'ultimaterewards'
      or regexp_replace(lower(coalesce(name, '')), '[^a-z0-9]', '', 'g')
          = 'ultimaterewards'
  );

alter table public.plaid_credit_accounts enable row level security;
drop policy if exists "Users can read their own Plaid credit accounts"
    on public.plaid_credit_accounts;
create policy "Users can read their own Plaid credit accounts"
    on public.plaid_credit_accounts
    for select
    to authenticated
    using (auth.uid() = user_id);
revoke all on public.plaid_credit_accounts from anon, authenticated;
grant select on public.plaid_credit_accounts to authenticated;

create table if not exists public.plaid_liability_snapshots (
    snapshot_id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    account_id text not null,
    statement_issue_date date not null,
    statement_balance numeric(14, 2),
    minimum_payment_amount numeric(14, 2),
    next_payment_due_date date,
    iso_currency_code text,
    fetched_at timestamptz not null default now(),
    foreign key (user_id, account_id)
        references public.plaid_credit_accounts(user_id, account_id)
        on delete cascade,
    unique (user_id, account_id, statement_issue_date)
);

create index if not exists plaid_liability_snapshots_cycle_idx
    on public.plaid_liability_snapshots
        (user_id, account_id, statement_issue_date desc);

alter table public.plaid_liability_snapshots enable row level security;
drop policy if exists "Users can read their own Plaid liability snapshots"
    on public.plaid_liability_snapshots;
create policy "Users can read their own Plaid liability snapshots"
    on public.plaid_liability_snapshots
    for select
    to authenticated
    using (auth.uid() = user_id);
revoke all on public.plaid_liability_snapshots from anon, authenticated;
grant select on public.plaid_liability_snapshots to authenticated;

create table if not exists public.plaid_liability_sync_state (
    user_id uuid primary key references auth.users(id) on delete cascade,
    status text not null check (status in ('synced', 'unavailable')),
    reason text,
    account_count integer not null default 0,
    statement_count integer not null default 0,
    updated_at timestamptz not null default now()
);

alter table public.plaid_liability_sync_state enable row level security;
drop policy if exists "Users can read their own Plaid liability sync state"
    on public.plaid_liability_sync_state;
create policy "Users can read their own Plaid liability sync state"
    on public.plaid_liability_sync_state
    for select
    to authenticated
    using (auth.uid() = user_id);
revoke all on public.plaid_liability_sync_state from anon, authenticated;
grant select on public.plaid_liability_sync_state to authenticated;

create table if not exists public.card_statement_summaries (
    user_id uuid not null references auth.users(id) on delete cascade,
    account_id text not null,
    statement_issue_date date not null,
    cycle_start_date date,
    cycle_end_date date not null,
    primary_person_id uuid not null
        references public.household_people(person_id) on delete cascade,
    status text not null
        check (status in ('READY', 'NEEDS_PRIOR_STATEMENT', 'REVIEW')),
    amount_owed numeric(14, 2),
    primary_transaction_count integer not null default 0,
    excluded_transaction_count integer not null default 0,
    excluded_amount numeric(14, 2) not null default 0,
    review_event_count integer not null default 0,
    statement_balance numeric(14, 2),
    details jsonb not null default '{}'::jsonb,
    updated_at timestamptz not null default now(),
    primary key (user_id, account_id, statement_issue_date),
    foreign key (user_id, account_id)
        references public.plaid_credit_accounts(user_id, account_id)
        on delete cascade
);

create index if not exists card_statement_summaries_user_cycle_idx
    on public.card_statement_summaries
        (user_id, statement_issue_date desc);

alter table public.card_statement_summaries enable row level security;
drop policy if exists "Users can read their own card statement summaries"
    on public.card_statement_summaries;
create policy "Users can read their own card statement summaries"
    on public.card_statement_summaries
    for select
    to authenticated
    using (auth.uid() = user_id);
revoke all on public.card_statement_summaries from anon, authenticated;
grant select on public.card_statement_summaries to authenticated;

create table if not exists public.card_cycle_start_overrides (
    user_id uuid not null references auth.users(id) on delete cascade,
    account_id text not null,
    statement_issue_date date not null,
    cycle_start_date date not null,
    updated_at timestamptz not null default now(),
    primary key (user_id, account_id, statement_issue_date),
    foreign key (user_id, account_id)
        references public.plaid_credit_accounts(user_id, account_id)
        on delete cascade,
    check (cycle_start_date < statement_issue_date)
);

alter table public.card_cycle_start_overrides enable row level security;
drop policy if exists "Users can read their own card cycle start overrides"
    on public.card_cycle_start_overrides;
create policy "Users can read their own card cycle start overrides"
    on public.card_cycle_start_overrides
    for select
    to authenticated
    using (auth.uid() = user_id);
revoke all on public.card_cycle_start_overrides from anon, authenticated;
grant select on public.card_cycle_start_overrides to authenticated;
