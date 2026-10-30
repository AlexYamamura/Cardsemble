-- Adds per-card configuration to plaid_credit_accounts so users can mark a card
-- as individual or household and choose a default assignee for its transactions.
-- Config columns survive Plaid syncs because savePlaidCreditAccounts only
-- upserts its own explicitly provided fields; config_updated_at tracks config
-- freshness separately from updated_at (which Plaid sync rewrites).

alter table public.plaid_credit_accounts
  add column if not exists card_type text not null default 'individual';

alter table public.plaid_credit_accounts
  add column if not exists default_assignee_mode text not null default 'person';

alter table public.plaid_credit_accounts
  add column if not exists default_assignee_person_id uuid;

alter table public.plaid_credit_accounts
  add column if not exists config_updated_at timestamptz not null default now();

alter table public.plaid_credit_accounts
  drop constraint if exists plaid_credit_accounts_card_type_check;
alter table public.plaid_credit_accounts
  add constraint plaid_credit_accounts_card_type_check
    check (card_type in ('individual', 'household'));

alter table public.plaid_credit_accounts
  drop constraint if exists plaid_credit_accounts_assignee_mode_check;
alter table public.plaid_credit_accounts
  add constraint plaid_credit_accounts_assignee_mode_check
    check (default_assignee_mode in ('person', 'shared', 'split'));

-- Individual cards are always assigned to the household default person ("you").
alter table public.plaid_credit_accounts
  drop constraint if exists plaid_credit_accounts_individual_mode_check;
alter table public.plaid_credit_accounts
  add constraint plaid_credit_accounts_individual_mode_check
    check (card_type = 'household' or default_assignee_mode = 'person');

-- Only person mode may carry a person id.
alter table public.plaid_credit_accounts
  drop constraint if exists plaid_credit_accounts_assignee_person_mode_check;
alter table public.plaid_credit_accounts
  add constraint plaid_credit_accounts_assignee_person_mode_check
    check (default_assignee_mode = 'person' or default_assignee_person_id is null);

-- Individual cards must not pin a person.
alter table public.plaid_credit_accounts
  drop constraint if exists plaid_credit_accounts_individual_person_check;
alter table public.plaid_credit_accounts
  add constraint plaid_credit_accounts_individual_person_check
    check (card_type = 'household' or default_assignee_person_id is null);

alter table public.plaid_credit_accounts
  drop constraint if exists plaid_credit_accounts_assignee_person_fk;
alter table public.plaid_credit_accounts
  add constraint plaid_credit_accounts_assignee_person_fk
    foreign key (user_id, default_assignee_person_id)
    references public.household_people (user_id, person_id)
    on delete set null;

create index if not exists plaid_credit_accounts_assignee_person_idx
  on public.plaid_credit_accounts (user_id, default_assignee_person_id)
  where default_assignee_person_id is not null;

-- Backfill existing rows as individual cards assigned to "you" (mode person,
-- person id null) so current behavior is unchanged.
update public.plaid_credit_accounts
set card_type = 'individual',
    default_assignee_mode = 'person',
    default_assignee_person_id = null,
    config_updated_at = now()
where card_type <> 'individual'
   or default_assignee_mode <> 'person'
   or default_assignee_person_id is not null;
