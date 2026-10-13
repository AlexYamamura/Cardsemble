-- Create household_members table for linking multiple Supabase users to a household
CREATE TABLE public.household_members (
    household_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    role text NOT NULL DEFAULT 'member' CHECK (role IN ('owner', 'member')),
    joined_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (household_id, user_id)
);

-- Enable RLS
ALTER TABLE public.household_members ENABLE ROW LEVEL SECURITY;

-- Policy: Users can see members of households they belong to
CREATE POLICY "Users can view household members of their household"
    ON public.household_members
    FOR SELECT
    TO authenticated
    USING (
        household_id = auth.uid() 
        OR user_id = auth.uid()
        OR EXISTS (
            SELECT 1 FROM public.household_members hm 
            WHERE hm.household_id = household_members.household_id 
            AND hm.user_id = auth.uid()
        )
    );

-- Policy: Household owner can add members
CREATE POLICY "Household owner can add members"
    ON public.household_members
    FOR INSERT
    TO authenticated
    WITH CHECK (
        household_id = auth.uid() 
        AND role = 'member'
    );

-- Policy: Users can remove themselves, owner can remove anyone
CREATE POLICY "Users can manage household membership"
    ON public.household_members
    FOR DELETE
    TO authenticated
    USING (
        user_id = auth.uid() 
        OR household_id = auth.uid()
    );

-- Index for faster lookups
CREATE INDEX idx_household_members_user_id ON public.household_members(user_id);

-- Grant permissions
GRANT SELECT, INSERT, DELETE ON public.household_members TO authenticated;