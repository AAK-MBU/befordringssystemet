-- Migration 038: Rename hjemmel "§ 26, stk. 1 afstand" to "§ 26, stk. 1 afstand/farlig skolevej"
-- Run once against the target database (dev / test / prod).
-- Safe to re-run: the update only touches a row that still has the old text.
--
-- Context (RITM0531496):
--   § 26, stk. 1 covers two grounds: nr. 1 (afstand) and nr. 2 (farlig
--   skolevej). The hjemmel only named the first, although bevillinger and
--   afslag on farlig skolevej are filed under it too. The afgørelsesbreve
--   already name both grounds separately, so only the hjemmel text changes.
--
-- What changes for users:
--   * The text is changed on the ONE Hjemmel row. Every bevilling points at
--     it by id, so all bevillinger, old ones included, show the new text at
--     once. No bevilling row is touched.
--   * The hjemmel text reaches the letter data (view_Letter_BevillingData,
--     column "hjemmel"), so a template that prints {hjemmel} prints the new
--     text in letters generated from now on.
--
-- Depends on the frontend (frontend/src/lib/lookupFilters.ts):
--   The frontend decides which hjemler and afgørelsesbreve may be chosen by
--   matching on the hjemmel TEXT. It accepts both the old and the new text,
--   so this migration and the frontend can go live in either order. Remove
--   the alias there once this has run in every environment.
--
-- Undo (if ever needed):
--   UPDATE [befordring].[Hjemmel]
--   SET    hjemmel_tekst = '§ 26, stk. 1 afstand'
--   WHERE  hjemmel_tekst = '§ 26, stk. 1 afstand/farlig skolevej';
--
-- Matching seed scripts (already updated, no action needed):
--   backend/db/seed/seed_lookup_data.sql
--   backend/db/seed/seed_test_data.sql

USE [Befordringssystemet];   -- adjust database name if different in your environment
GO

-- -----------------------------------------------------------------------
-- 1. Rename
--
--    Skipped if the new text already exists, so a re-run, or a database
--    that was seeded with the new text, never ends up with two rows of the
--    same hjemmel.
-- -----------------------------------------------------------------------
UPDATE [befordring].[Hjemmel]
SET    hjemmel_tekst = '§ 26, stk. 1 afstand/farlig skolevej'
WHERE  LTRIM(RTRIM(hjemmel_tekst)) = '§ 26, stk. 1 afstand'
  AND  NOT EXISTS (
        SELECT 1 FROM [befordring].[Hjemmel] h
        WHERE  LTRIM(RTRIM(h.hjemmel_tekst)) = '§ 26, stk. 1 afstand/farlig skolevej'
       );
PRINT CONCAT('Hjemmel: ', @@ROWCOUNT, ' row(s) renamed (expected 1 on first run, 0 on a re-run).');
GO

-- -----------------------------------------------------------------------
-- 2. Verify: the new text is present exactly once, the old one is gone
-- -----------------------------------------------------------------------
SELECT hjemmel_id, hjemmel_tekst, aktiv,
       (SELECT COUNT(*) FROM [befordring].[Bevilling] b WHERE b.hjemmel_id = h.hjemmel_id) AS antal_bevillinger
FROM   [befordring].[Hjemmel] h
WHERE  hjemmel_tekst LIKE '§ 26, stk. 1 afstand%'
ORDER  BY hjemmel_id;
