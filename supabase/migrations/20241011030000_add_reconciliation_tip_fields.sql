-- Add is_tip and tip_percentage columns to card_event_reconciliations for tip detection
alter table public.card_event_reconciliations
    add column if not exists is_tip boolean not null default false;

alter table public.card_event_reconciliations
    add column if not exists tip_percentage numeric(5, 2);

-- Grant INSERT on new columns to authenticated
grant insert (event_id, user_id, candidate_transaction_id, status, event_amount, plaid_amount, amount_difference, is_tip, tip_percentage, details, updated_at) on table public.card_event_reconciliations to authenticated;
