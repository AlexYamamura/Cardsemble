-- Add household_visible column to plaid_transactions
ALTER TABLE public.plaid_transactions
ADD COLUMN IF NOT EXISTS household_visible boolean NOT NULL DEFAULT true;

-- Add household_visible column to card_events
ALTER TABLE public.card_events
ADD COLUMN IF NOT EXISTS household_visible boolean NOT NULL DEFAULT true;

-- Grant update permission on household_visible for authenticated users
GRANT UPDATE (household_visible) ON TABLE public.plaid_transactions TO authenticated;
GRANT UPDATE (household_visible) ON TABLE public.card_events TO authenticated;

-- Create policies for household_visible updates
DROP POLICY IF EXISTS "Users can update household_visible on their Plaid transactions" ON public.plaid_transactions;
CREATE POLICY "Users can update household_visible on their Plaid transactions"
    ON public.plaid_transactions
    FOR UPDATE
    TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update household_visible on their card events" ON public.card_events;
CREATE POLICY "Users can update household_visible on their card events"
    ON public.card_events
    FOR UPDATE
    TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);