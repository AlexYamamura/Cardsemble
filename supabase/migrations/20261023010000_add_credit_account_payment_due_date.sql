-- 20261023010000_add_credit_account_payment_due_date.sql
-- Store Plaid's liabilities.credit[].next_payment_due_date on
-- plaid_credit_accounts so the Wallet tab can surface the next payment due
-- date per card. Populated by syncPlaidLiabilities from /liabilities/get.
-- Apply before deploying the updated edge function.

alter table public.plaid_credit_accounts
    add column if not exists next_payment_due_date date;

-- The existing own-row SELECT policy already covers this column; no new
-- grants are required because the Wallet tab reads it via the statement
-- cycles endpoint, which uses the service-role client.
