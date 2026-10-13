-- Add invite_code column to household_members for the owner's invite code
-- The owner (household_id = user_id) gets an invite code that others can use to join
ALTER TABLE public.household_members
ADD COLUMN IF NOT EXISTS invite_code text UNIQUE;

-- Create index for invite code lookups
CREATE INDEX IF NOT EXISTS idx_household_members_invite_code ON public.household_members(invite_code);

-- Function to generate a random invite code
CREATE OR REPLACE FUNCTION generate_invite_code()
RETURNS text AS $$
DECLARE
  chars text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; -- No confusing chars
  code text := '';
  i int;
BEGIN
  FOR i IN 1..8 LOOP
    code := code || substr(chars, floor(random() * length(chars) + 1)::int, 1);
  END LOOP;
  RETURN code;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger to auto-generate invite code for household owners
CREATE OR REPLACE FUNCTION set_owner_invite_code()
RETURNS trigger AS $$
BEGIN
  -- Only set invite code for the household owner (where household_id = user_id)
  IF NEW.household_id = NEW.user_id AND NEW.invite_code IS NULL THEN
    NEW.invite_code := generate_invite_code();
    -- Ensure uniqueness (retry if collision)
    WHILE EXISTS (SELECT 1 FROM public.household_members WHERE invite_code = NEW.invite_code) LOOP
      NEW.invite_code := generate_invite_code();
    END LOOP;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trigger_set_owner_invite_code ON public.household_members;
CREATE TRIGGER trigger_set_owner_invite_code
  BEFORE INSERT ON public.household_members
  FOR EACH ROW
  EXECUTE FUNCTION set_owner_invite_code();

-- Grant execute on function
GRANT EXECUTE ON FUNCTION generate_invite_code() TO authenticated;