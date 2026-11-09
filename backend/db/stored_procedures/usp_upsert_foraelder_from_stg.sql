USE [Befordringssystemet]
GO

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

/*
    Merge the nightly guardian load from Foraelder_STG into Foraelder.

    Same contract as usp_upsert_elev_from_stg: the data worker's job owns the
    stage and is the authority on the columns it carries, so a NULL arriving in
    STG overwrites. No load_id on the table, so the stage is processed whole
    and NOT cleared afterwards — it belongs to the other job.

    Matched on the composite key (cpr_foraelder, cpr_elev): a guardian appears
    once per child, so the same adult can legitimately have several rows.

    Not copied, and why:

      adresse_id              Always NULL in STG. Resolved separately from
                              LOIS.CPR.PersonGeoView — see
                              usp_upsert_adresse_ids_from_stg.

    maa_vide_barns_adresse IS copied, as of the LIS transfer carrying it. It
    was excluded while nothing populated the stage column — the note here used
    to read "remove it from this list when the import should own it", and the
    import now does.

    It takes the same contract as everything else above: the stage is the
    authority, so a NULL arriving in STG overwrites. Worth knowing for this
    column in particular, because the sag page renders a NULL as a red "Nej"
    rather than a blank, and the table's DEFAULT of 1 only applies to an INSERT
    that omits the column — which this one no longer does.

    Guardians whose child is not in Elev are skipped rather than failing the
    batch. FK_Foraelder_Elev would reject them, and the two loads can
    legitimately arrive out of step; the count is returned so a persistent
    mismatch is visible instead of silent.
*/

CREATE OR ALTER PROCEDURE [befordring].[usp_upsert_foraelder_from_stg]
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @staged_rows     INT = 0;
    DECLARE @duplicate_keys  INT = 0;
    DECLARE @skipped_no_elev INT = 0;
    DECLARE @updated_rows    INT = 0;
    DECLARE @inserted_rows   INT = 0;

    BEGIN TRY
        BEGIN TRANSACTION;

            /* One row per (cpr_foraelder, cpr_elev). No load_id or identity to
               order by, so a duplicate key is resolved arbitrarily and
               counted. Rows missing either half of the key are dropped. */
            ;WITH SourceRows AS
            (
                SELECT
                    *,
                    ROW_NUMBER() OVER (
                        PARTITION BY LTRIM(RTRIM(cpr_foraelder)), LTRIM(RTRIM(cpr_elev))
                        ORDER BY     (SELECT NULL)
                    ) AS rn
                FROM [befordring].[Foraelder_STG]
                WHERE NULLIF(LTRIM(RTRIM(cpr_foraelder)), '') IS NOT NULL
                AND   NULLIF(LTRIM(RTRIM(cpr_elev)), '')      IS NOT NULL
            )
            SELECT
                LTRIM(RTRIM(cpr_foraelder)) AS cpr_foraelder,
                LTRIM(RTRIM(cpr_elev))      AS cpr_elev,
                adresseringsnavn,
                navne_adresse_beskyttelse,
                maa_vide_barns_adresse,
                relation
            INTO #Source
            FROM SourceRows
            WHERE rn = 1;

            SELECT @staged_rows = COUNT(*) FROM #Source;

            SELECT @duplicate_keys =
                (SELECT COUNT(*) FROM [befordring].[Foraelder_STG]
                 WHERE NULLIF(LTRIM(RTRIM(cpr_foraelder)), '') IS NOT NULL
                 AND   NULLIF(LTRIM(RTRIM(cpr_elev)), '')      IS NOT NULL)
                - @staged_rows;

            /* Drop guardians whose child we do not have. Counted first so the
               number is reported rather than inferred from a row difference. */
            SELECT @skipped_no_elev = COUNT(*)
            FROM   #Source s
            WHERE  NOT EXISTS (SELECT 1 FROM [befordring].[Elev] e
                               WHERE e.cpr = s.cpr_elev);

            DELETE s
            FROM   #Source s
            WHERE  NOT EXISTS (SELECT 1 FROM [befordring].[Elev] e
                               WHERE e.cpr = s.cpr_elev);

            CREATE UNIQUE CLUSTERED INDEX IX_Source_key
            ON #Source (cpr_foraelder, cpr_elev);

            /* EXCEPT rather than "<>": it treats NULL as equal to NULL, so an
               unchanged row is not rewritten just because a value is NULL. */
            UPDATE target
            SET
                target.adresseringsnavn          = source.adresseringsnavn,
                target.navne_adresse_beskyttelse = source.navne_adresse_beskyttelse,
                target.maa_vide_barns_adresse    = source.maa_vide_barns_adresse,
                target.relation                  = source.relation
            FROM [befordring].[Foraelder] target
            JOIN #Source source
                ON  source.cpr_foraelder = target.cpr_foraelder
                AND source.cpr_elev      = target.cpr_elev
            WHERE EXISTS
            (
                SELECT
                    target.adresseringsnavn,
                    target.navne_adresse_beskyttelse,
                    target.maa_vide_barns_adresse,
                    target.relation

                EXCEPT

                SELECT
                    source.adresseringsnavn,
                    source.navne_adresse_beskyttelse,
                    source.maa_vide_barns_adresse,
                    source.relation
            );

            SET @updated_rows = @@ROWCOUNT;

            INSERT INTO [befordring].[Foraelder]
            (
                cpr_foraelder,
                cpr_elev,
                adresseringsnavn,
                navne_adresse_beskyttelse,
                maa_vide_barns_adresse,
                relation
            )
            SELECT
                source.cpr_foraelder,
                source.cpr_elev,
                source.adresseringsnavn,
                source.navne_adresse_beskyttelse,
                source.maa_vide_barns_adresse,
                source.relation
            FROM #Source source
            WHERE NOT EXISTS
            (
                SELECT 1
                FROM   [befordring].[Foraelder] target
                WHERE  target.cpr_foraelder = source.cpr_foraelder
                AND    target.cpr_elev      = source.cpr_elev
            );

            SET @inserted_rows = @@ROWCOUNT;

        COMMIT TRANSACTION;

        SELECT
            @staged_rows     AS staged_rows,
            @duplicate_keys  AS duplicate_keys_dropped,
            @skipped_no_elev AS skipped_child_not_in_elev,
            @updated_rows    AS updated_rows,
            @inserted_rows   AS inserted_rows;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH;
END;
GO
