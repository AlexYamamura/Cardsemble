-- 20261023000000_add_credit_account_balances.sql
-- Store Plaid account balances (credit limit + current balance) on
-- plaid_credit_accounts so the Wallet tab can surface per-card and
-- aggregation data (total credit limit, total utilization, number of cards).
-- Apply before deploying the updated edge function.

alter table public.plaid_credit_accounts
    add column if not exists credit_limit numeric(14, 2);

alter table public.plaid_credit_accounts
    add column if not exists current_balance numeric(14, 2);
