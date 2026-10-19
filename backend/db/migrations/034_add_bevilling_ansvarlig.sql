-- Migration 034: Add ansvarlig_sagsbehandler_id and ansvarlig_ppr_sagsbehandler_id
-- Run once against the target database (test / prod).
-- Safe to re-run — the IF NOT EXISTS guards make it idempotent.
--
-- The problem:
--   Nearly every bevilling already carries a sagsbehandler and a PPR-
--   sagsbehandler by the time it reaches revurdering or genbehandling — they
--   are set when the bevilling is created. So the worklists showed two filled
--   name fields on every single row, and a caseworker scanning the page read
--   that as "somebody already has this one". Almost always untrue: the names
--   say who handled the ORIGINAL decision, not who is doing the revurdering.
--
-- Why not just clear the existing columns when a bevilling enters revurdering:
--   1. The names are wanted as history — that is the whole reason they are on
--      the bevilling.
--   2. "Entering revurdering" is not an event. Bevilling.revurdering is a flag
--      usp_recalculate_bevilling_status recomputes from scratch on every run,
--      including a "stay" branch that holds it at 1 until BR signs off. Any
--      clear-on-entry rule therefore runs again every night, and would wipe an
--      assignment a caseworker made that afternoon.
--   3. sagsbehandler_id feeds the status calculation ('Påbegyndt' vs 'Ny'), so
--      emptying it reaches further than the worklist.
--
-- What these two columns are:
--   Who is handling the bevilling's PENDING work, right now. NULL is the
--   normal state and means exactly one thing: nobody has picked it up. That is
--   the signal the worklists were missing.
--
--   One pair, not two: needs_revurdering and needs_genbehandling are computed
--   independently and a bevilling can carry both flags at once, but it is the
--   same person doing the work either way.
--
-- Lifecycle:
--   Set from the revurderings- and genbehandlingssiden, and NOTHING else is
--   written when they are. sagsbehandler_id and ppr_sagsbehandler_id keep
--   whatever they held: view_Letter_BevillingData resolves {sagsbehandler} on
--   the afgørelsesbrev from sagsbehandler_id, so a case changing hands for a
--   revurdering would otherwise rewrite the name on a letter that has already
--   gone out. The bevilling has to keep matching its own letter.
--
--   Cleared when the work completes — BR sign-off (revurderet_af_br) or the
--   genbehandling sign-off — in BevillingService.update_bevilling, which
--   already handles that kind of transition. Completion is a real user action,
--   unlike entry, so the clear happens once and cannot repeat.
--
-- Not backfilled:
--   Every existing row starts NULL, which is correct — nobody has claimed any
--   of them yet.

USE [Befordringssystemet];
GO

-- -----------------------------------------------------------------------
-- 1. Columns
-- -----------------------------------------------------------------------
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID(N'[befordring].[Bevilling]')
    AND   name      = N'ansvarlig_sagsbehandler_id'
)
BEGIN
    ALTER TABLE [befordring].[Bevilling]
    ADD [ansvarlig_sagsbehandler_id] INT NULL;

    PRINT 'Added Bevilling.ansvarlig_sagsbehandler_id.';
END
ELSE
BEGIN
    PRINT 'Bevilling.ansvarlig_sagsbehandler_id already exists - nothing to do.';
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID(N'[befordring].[Bevilling]')
    AND   name      = N'ansvarlig_ppr_sagsbehandler_id'
)
BEGIN
    ALTER TABLE [befordring].[Bevilling]
    ADD [ansvarlig_ppr_sagsbehandler_id] INT NULL;

    PRINT 'Added Bevilling.ansvarlig_ppr_sagsbehandler_id.';
END
ELSE
BEGIN
    PRINT 'Bevilling.ansvarlig_ppr_sagsbehandler_id already exists - nothing to do.';
END
GO

-- -----------------------------------------------------------------------
-- 2. Foreign keys
--
-- Separate batches: the columns have to exist before they can be
-- constrained, and GO is what makes the ALTERs above visible to the parser.
-- -----------------------------------------------------------------------
IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = N'FK_Bevilling_AnsvarligSagsbehandler'
)
BEGIN
    ALTER TABLE [befordring].[Bevilling]
    ADD CONSTRAINT [FK_Bevilling_AnsvarligSagsbehandler]
        FOREIGN KEY ([ansvarlig_sagsbehandler_id])
        REFERENCES [befordring].[Sagsbehandler] ([sagsbehandler_id]);

    PRINT 'Added FK_Bevilling_AnsvarligSagsbehandler.';
END
ELSE
BEGIN
    PRINT 'FK_Bevilling_AnsvarligSagsbehandler already exists - nothing to do.';
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = N'FK_Bevilling_AnsvarligPprSagsbehandler'
)
BEGIN
    ALTER TABLE [befordring].[Bevilling]
    ADD CONSTRAINT [FK_Bevilling_AnsvarligPprSagsbehandler]
        FOREIGN KEY ([ansvarlig_ppr_sagsbehandler_id])
        REFERENCES [befordring].[PPR_Sagsbehandler] ([ppr_sagsbehandler_id]);

    PRINT 'Added FK_Bevilling_AnsvarligPprSagsbehandler.';
END
ELSE
BEGIN
    PRINT 'FK_Bevilling_AnsvarligPprSagsbehandler already exists - nothing to do.';
END
GO

-- -----------------------------------------------------------------------
-- 3. Verify
-- -----------------------------------------------------------------------
SELECT c.name       AS kolonne,
       t.name       AS datatype,
       c.is_nullable
FROM   sys.columns c
JOIN   sys.types   t ON t.user_type_id = c.user_type_id
WHERE  c.object_id = OBJECT_ID(N'[befordring].[Bevilling]')
AND    c.name IN (N'ansvarlig_sagsbehandler_id', N'ansvarlig_ppr_sagsbehandler_id');

SELECT fk.name AS foreign_key,
       OBJECT_NAME(fk.referenced_object_id) AS refererer_til
FROM   sys.foreign_keys fk
WHERE  fk.name IN (N'FK_Bevilling_AnsvarligSagsbehandler',
                   N'FK_Bevilling_AnsvarligPprSagsbehandler');
