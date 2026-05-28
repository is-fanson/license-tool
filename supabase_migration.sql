-- ============================================================
-- Supabase Migration: licenses table for claude-ds-install-license
-- Run this in Supabase SQL Editor
-- ============================================================

-- 1. Add missing columns (safe to re-run)
ALTER TABLE licenses ADD COLUMN IF NOT EXISTS fingerprint  text;
ALTER TABLE licenses ADD COLUMN IF NOT EXISTS actived_at   timestamptz;
ALTER TABLE licenses ADD COLUMN IF NOT EXISTS expires_at   timestamptz;

-- 2. Drop redundant column added by previous script (if exists)
ALTER TABLE licenses DROP COLUMN IF EXISTS machine_id;

-- 3. Enable RLS (skip if already enabled)
ALTER TABLE licenses ENABLE ROW LEVEL SECURITY;

-- 4. Allow public read by license_key (needed for validation)
DROP POLICY IF EXISTS "Allow select by license_key" ON licenses;
CREATE POLICY "Allow select by license_key"
  ON licenses FOR SELECT
  USING (true);

-- 5. Allow public update by license_key (needed for machine binding)
DROP POLICY IF EXISTS "Allow update by license_key" ON licenses;
CREATE POLICY "Allow update by license_key"
  ON licenses FOR UPDATE
  USING (true)
  WITH CHECK (true);

-- 6. Allow public insert (needed for license generator web page)
DROP POLICY IF EXISTS "Allow insert" ON licenses;
CREATE POLICY "Allow insert"
  ON licenses FOR INSERT
  WITH CHECK (true);

-- 7. Verify final schema
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'licenses'
ORDER BY ordinal_position;
