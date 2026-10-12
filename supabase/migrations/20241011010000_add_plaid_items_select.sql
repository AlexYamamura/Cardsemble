-- Migration: Add SELECT policy for plaid_items table
-- The mobile app reads plaid_items directly via the Supabase client
-- to list Plaid connections. This policy is required for that.

drop policy if exists "Users can read their own plaid items" on public.plaid_items;
create policy "Users can read their own plaid items"
    on public.plaid_items
    for select
    to authenticated
    using (auth.uid() = user_id);

grant select (item_id, institution_id, institution_name, status, created_at, user_id) on table public.plaid_items to authenticated;
