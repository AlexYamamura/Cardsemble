-- Add source tracking to plaid_transactions
ALTER TABLE plaid_transactions 
ADD COLUMN IF NOT EXISTS source text DEFAULT 'plaid';

-- Valid sources
COMMENT ON COLUMN plaid_transactions.source IS 'Source of transaction: plaid, csv_import, manual';

-- CSV import history for audit trail
CREATE TABLE IF NOT EXISTS csv_import_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id),
  account_id text NOT NULL,
  filename text,
  total_rows int NOT NULL,
  new_count int DEFAULT 0,
  duplicate_count int DEFAULT 0,
  error_count int DEFAULT 0,
  created_at timestamptz DEFAULT now()
);

-- RLS policies for csv_import_history
ALTER TABLE csv_import_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own import history"
  ON csv_import_history FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own import history"
  ON csv_import_history FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Index for faster lookups
CREATE INDEX IF NOT EXISTS idx_csv_import_history_user_id 
  ON csv_import_history (user_id, created_at DESC);