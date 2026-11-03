-- Migration 036: Add the genbehandling_haandteret_stamdata sign-off flag
-- Run once against the target database (test / prod).
-- Safe to re-run — the IF NOT EXISTS guard makes it idempotent.
--
-- Context:
--   Genbehandling has so far fired on DRIFT: the bevilling's skolekode or
--   adresse disagreeing with the student's current CPR data. Both mismatch
--   expressions in usp_recalculate_bevilling_status guard on data existing on
--   BOTH sides, so a student with no stamdata at all never raised anything —
--   the one case where the bevilling cannot be checked was also the one case
--   nobody was told about. 26 active/kommende bevillinger were in that state;
--   see backend/db/analyse/elever_uden_stamdata_med_aktiv_bevilling.sql.
--
--   Befordring asked for them to be flagged too: "Du må meget gerne sætte det
--   op, så de også bliver sendt til genbehandling, når der mangler stamdata at
--   sammenholde med."
--
--   That needs a sign-off flag of its own:
--
--     genbehandling_haandteret_stamdata  BIT — set when a caseworker signs off
--                                        a genbehandling raised because the
--                                        stamdata was MISSING.
--
--   Why not reuse the two snapshot columns from migration 011. Those record
--   the VALUE the caseworker reviewed, so the SP can tell new drift from drift
--   already acknowledged. A missing value has nothing to snapshot: writing
--   NULL is indistinguishable from never having signed off, the SP's
--   "... IS NULL" entry condition fires on the very next run, and the
--   bevilling bounces straight back onto the list — permanently, because the
--   data that would end the loop is the data that is missing. A BIT says
--   "this absence has been seen", which is the fact that actually needs
--   storing.
--
--   The SP clears it again the moment the stamdata arrives, so a student whose
--   data goes missing a second time is flagged a second time.
--
-- After running this migration, deploy the updated backend and run the updated
-- usp_recalculate_bevilling_status.sql and view_Genbehandling.sql scripts.
-- The view change is NOT optional: it currently INNER JOINs Elev and Adresse,
-- so without it these bevillinger are flagged in the table and still never
-- reach the page.

USE [Befordringssystemet];
GO

-- -----------------------------------------------------------------------
-- 1. genbehandling_haandteret_stamdata sign-off flag
-- -----------------------------------------------------------------------
IF NOT EXISTS (
    SELECT 1
    FROM   sys.columns
    WHERE  object_id = OBJECT_ID(N'[befordring].[Bevilling]')
    AND    name      = N'genbehandling_haandteret_stamdata'
)
BEGIN
    ALTER TABLE [befordring].[Bevilling]
        ADD genbehandling_haandteret_stamdata BIT NULL;

    PRINT 'Column genbehandling_haandteret_stamdata added to [befordring].[Bevilling].';
END
ELSE
BEGIN
    PRINT 'Column genbehandling_haandteret_stamdata already exists — skipped.';
END
GO

-- -----------------------------------------------------------------------
-- 2. Verify
-- -----------------------------------------------------------------------

-- 2a. The column exists, alongside the two snapshot columns it sits next to.
SELECT
    c.name          AS column_name,
    t.name          AS data_type,
    c.is_nullable   AS is_nullable
FROM      sys.columns AS c
JOIN      sys.types   AS t ON t.user_type_id = c.user_type_id
WHERE     c.object_id = OBJECT_ID(N'[befordring].[Bevilling]')
AND       c.name IN (
              N'genbehandling_haandteret_adresse_id',
              N'genbehandling_haandteret_skolekode',
              N'genbehandling_haandteret_stamdata'
          )
ORDER BY  c.name;

-- 2b. How many bevillinger the new trigger will pick up on the next run of
--     usp_recalculate_bevilling_status. Read this BEFORE running the SP: it is
--     the number of cards that are about to appear on the genbehandling page,
--     and Befordring would rather know than be surprised by it.
--
--     Same shape as the trigger itself — the bevilling has a value and the
--     student has nothing to compare it against.
SELECT
    COUNT(*)                                                              AS i_alt,
    SUM(CASE WHEN e.cpr IS NULL THEN 1 ELSE 0 END)                        AS uden_elevraekke,
    SUM(CASE WHEN b.matrikel_id IS NOT NULL
              AND ISNULL(e.skolekode, 0) = 0 THEN 1 ELSE 0 END)           AS mangler_skolekode,
    SUM(CASE WHEN b.adresse_id IS NOT NULL
              AND e.adresse_id IS NULL       THEN 1 ELSE 0 END)           AS mangler_adresse
FROM       [befordring].[Bevilling] b
INNER JOIN [befordring].[Status]    s ON s.status_id = b.status_id
LEFT  JOIN [befordring].[Elev]      e ON e.cpr       = b.cpr_elev
WHERE      b.aktiv = 1
AND        s.status_tekst IN (N'Aktiv', N'Kommende')
AND        (
               e.cpr IS NULL
            OR (b.matrikel_id IS NOT NULL AND ISNULL(e.skolekode, 0) = 0)
            OR (b.adresse_id  IS NOT NULL AND e.adresse_id IS NULL)
           );
GO
