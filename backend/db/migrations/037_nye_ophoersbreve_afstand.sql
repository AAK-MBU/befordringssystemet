-- Migration 037: Two new afgørelsesbreve for ending a bevilling granted on distance
-- Run once against the target database (dev / test / prod).
-- Safe to re-run — the insert is guarded on the text.
--
-- Context:
--   Befordring has written two new letters in the skabelondokument:
--
--       Ophør: § 26, stk. 1, nr. 1 (afstand)
--       Ophør: § 26, stk. 1, nr. 2 (farlig skolevej)
--
--   Until now the Afgoerelsesbrev table held exactly one ophør letter —
--   "Påtænkt ophør: § 26, stk. 2 (sygdom)" — so a bevilling granted under
--   § 26, stk. 1 (afstand) had no letter of its own to end it with. These two
--   fill that gap: one per nummer of the paragraph.
--
--   They are ophør letters, not påtænkt ones: they END the kørsel rather than
--   announcing an intention to. The frontend derives that from the text (the
--   word "Ophør"), so no classification is stored here — see
--   frontend/src/lib/lookupFilters.ts.
--
-- Visibility, which is enforced in the frontend and not in the database:
--   status   = Ophørt
--   hjemmel  = § 26, stk. 1 afstand
--
--   The Afgoerelsesbrev table is a flat lookup with no foreign key to Hjemmel
--   or Status — every pairing in this system lives in lookupFilters.ts, keyed
--   on the exact texts below. Change a text here and the mapping there must
--   change with it.
--
-- Matching seed scripts (already updated, no action needed):
--   backend/db/seed/seed_lookup_data.sql
--   backend/db/seed/seed_test_data.sql

USE [Befordringssystemet];
GO

-- -----------------------------------------------------------------------
-- 1. The two new letters
-- -----------------------------------------------------------------------
INSERT INTO [befordring].[Afgoerelsesbrev] (afgoerelsesbrev_tekst, beskrivelse, aktiv)
SELECT v.afgoerelsesbrev_tekst, v.beskrivelse, v.aktiv
FROM (VALUES
    (N'Ophør: § 26, stk. 1, nr. 1 (afstand)',        N'', 1),
    (N'Ophør: § 26, stk. 1, nr. 2 (farlig skolevej)', N'', 1)
) AS v (afgoerelsesbrev_tekst, beskrivelse, aktiv)
WHERE NOT EXISTS (
    SELECT 1 FROM [befordring].[Afgoerelsesbrev] a
    WHERE LTRIM(RTRIM(a.afgoerelsesbrev_tekst)) = LTRIM(RTRIM(v.afgoerelsesbrev_tekst))
);
PRINT CONCAT('Afgoerelsesbrev: ', @@ROWCOUNT, ' row(s) inserted.');
GO

-- -----------------------------------------------------------------------
-- 2. Verify — the three ophør letters should now be present and aktiv
-- -----------------------------------------------------------------------
SELECT afgoerelsesbrev_id, afgoerelsesbrev_tekst, aktiv
FROM   [befordring].[Afgoerelsesbrev]
WHERE  afgoerelsesbrev_tekst LIKE N'%phør%'
ORDER  BY afgoerelsesbrev_tekst;
