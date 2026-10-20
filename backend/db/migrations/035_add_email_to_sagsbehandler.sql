-- Migration 035: Add email column to Sagsbehandler and PPR_Sagsbehandler
-- Run once against the target database (test / prod).
-- Safe to re-run — the column-existence guard makes it idempotent.
--
-- Context:
--   Enables the "Min side" feature, which shows each caseworker only the
--   bevillinger assigned to them. Identity is resolved by matching the
--   logged-in user's OIDC email claim against this column.
--
--   The column is nullable so existing rows are unaffected. Populate it
--   manually per environment with the caseworker's @aarhus.dk address:
--
--     UPDATE [befordring].[Sagsbehandler]
--     SET email = N'name@aarhus.dk'
--     WHERE sagsbehandler_tekst = N'Navn Navnesen';
--
--     UPDATE [befordring].[PPR_Sagsbehandler]
--     SET email = N'name@aarhus.dk'
--     WHERE ppr_sagsbehandler_tekst = N'Navn Navnesen';

USE [Befordringssystemet];   -- adjust database name if different in your environment
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID(N'[befordring].[Sagsbehandler]')
      AND name = N'email'
)
BEGIN
    ALTER TABLE [befordring].[Sagsbehandler]
    ADD email NVARCHAR(255) NULL;
    PRINT 'Sagsbehandler.email: column added.';
END
ELSE
BEGIN
    PRINT 'Sagsbehandler.email: column already exists, skipped.';
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID(N'[befordring].[PPR_Sagsbehandler]')
      AND name = N'email'
)
BEGIN
    ALTER TABLE [befordring].[PPR_Sagsbehandler]
    ADD email NVARCHAR(255) NULL;
    PRINT 'PPR_Sagsbehandler.email: column added.';
END
ELSE
BEGIN
    PRINT 'PPR_Sagsbehandler.email: column already exists, skipped.';
END
GO

SELECT sagsbehandler_id, sagsbehandler_tekst, email
FROM   [befordring].[Sagsbehandler]
ORDER BY sagsbehandler_tekst;
GO

SELECT ppr_sagsbehandler_id, ppr_sagsbehandler_tekst, email
FROM   [befordring].[PPR_Sagsbehandler]
ORDER BY ppr_sagsbehandler_tekst;
GO