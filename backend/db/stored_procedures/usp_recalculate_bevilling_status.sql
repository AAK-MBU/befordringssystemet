USE [Befordringssystemet]
GO

/****** Object:  StoredProcedure [befordring].[usp_recalculate_bevilling_status]    Script Date: 02/09/2026 13:52:09 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE OR ALTER PROCEDURE [befordring].[usp_recalculate_bevilling_status]
    @bevilling_id INT = NULL,
    @today DATE = NULL,
    @dry_run BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @today IS NULL
    BEGIN
        SET @today = CONVERT(DATE, GETDATE());
    END;

    DECLARE
        @target_cpr NVARCHAR(50),
        @fejlet_status_id INT;

    SELECT
        @fejlet_status_id = s.status_id
    FROM
        [befordring].[Status] s
    WHERE
        s.status_tekst = N'Fejlet'
        AND s.aktiv = 1;

    IF @fejlet_status_id IS NULL
    BEGIN
        THROW 50003, 'Status does not exist: Fejlet.', 1;
    END;

    IF @bevilling_id IS NOT NULL
    BEGIN
        SELECT
            @target_cpr = b.cpr_elev
        FROM
            [befordring].[Bevilling] b
        WHERE
            b.bevilling_id = @bevilling_id;

        IF @target_cpr IS NULL
            AND NOT EXISTS (
                SELECT 1
                FROM [befordring].[Bevilling]
                WHERE bevilling_id = @bevilling_id
            )
        BEGIN
            THROW 50001, 'Bevilling not found.', 1;
        END;
    END;

    ;WITH target_bevillinger AS (
        SELECT
            b.bevilling_id,
            b.cpr_elev,
            b.status_id AS current_status_id,
            s.status_tekst AS current_status_text,
            b.sagsbehandler_id,
            CONVERT(DATE, b.revurderingsdato) AS revurderingsdato,
            b.revurderet_af_ppr,
            b.revurderet_af_br,
            b.revurdering AS current_revurdering,
            b.genbehandling AS current_genbehandling,
            b.genbehandling_haandteret,
            CASE
                WHEN b.matrikel_id IS NOT NULL
                    AND ISNULL(e.skolekode, 0) <> 0
                    AND e.skolekode <> sm.skolekode
                THEN 1
                ELSE 0
            END AS skolekode_mismatch,
            CASE
                WHEN b.adresse_id IS NOT NULL
                    AND e.adresse_id IS NOT NULL
                    AND b.adresse_id <> e.adresse_id
                THEN 1
                ELSE 0
            END AS adresse_mismatch,
            /* The MISSING counterpart of the two mismatches above.

               Both of those guard on data existing on BOTH sides — and must,
               or an absent value would read as a disagreement and every
               student without stamdata would be reported as drifting. The
               cost is that the one case where the bevilling CANNOT be checked
               was also the one case nobody was told about: 26 active and
               kommende bevillinger sat in it, invisible, because being
               uncheckable looked exactly like being fine.

               Befordring asked for them: "Du må meget gerne sætte det op, så
               de også bliver sendt til genbehandling, når der mangler
               stamdata at sammenholde med."

               So these are deliberately the exact complement: the bevilling
               HAS a value and the student has nothing to hold it up against.
               Where the bevilling has no value either there is nothing to
               check in the first place and nothing is raised — that is an
               incomplete bevilling, which the status engine already answers
               for with Ny / Påbegyndt / Fejlet. */
            CASE
                WHEN b.matrikel_id IS NOT NULL
                    AND ISNULL(e.skolekode, 0) = 0
                THEN 1
                ELSE 0
            END AS mangler_skolekode,
            CASE
                WHEN b.adresse_id IS NOT NULL
                    AND e.adresse_id IS NULL
                THEN 1
                ELSE 0
            END AS mangler_adresse,
            /* No Elev row at all is the whole of the above and then some, but
               it is listed separately because it survives a bevilling that
               carries neither matrikel nor adresse — and a bevilling pointing
               at a citizen we hold no stamdata on is worth a caseworker's eye
               whatever else is missing. Elev is LEFT JOINed below, so this is
               the only place the distinction is visible. */
            CASE
                WHEN e.cpr IS NULL THEN 1
                WHEN b.matrikel_id IS NOT NULL AND ISNULL(e.skolekode, 0) = 0 THEN 1
                WHEN b.adresse_id IS NOT NULL AND e.adresse_id IS NULL THEN 1
                ELSE 0
            END AS stamdata_mangler,
            e.cpr         AS elev_findes,
            e.adresse_id  AS elev_adresse_id,
            e.skolekode   AS elev_skolekode,
            b.genbehandling_haandteret_adresse_id,
            b.genbehandling_haandteret_skolekode,
            b.genbehandling_haandteret_stamdata
        FROM
            [befordring].[Bevilling] b
        LEFT JOIN [befordring].[Status] s ON s.status_id = b.status_id
        LEFT JOIN [befordring].[Elev] e ON e.cpr = b.cpr_elev
        LEFT JOIN [befordring].[Skolematrikel] sm ON sm.matrikel_id = b.matrikel_id
        WHERE
            /* Soft-deleted bevillinger are invisible to the application, so they
               must not be given a status here either. Note the parentheses: the
               OR below has to be grouped before AND-ing the aktiv filter onto
               it, or the second branch would match deleted rows.

               Called with a @bevilling_id that has since been deleted, the
               procedure still resolves @target_cpr above and so recalculates
               that citizen's *remaining* bevillinger — which is what un-fails a
               survivor once its duplicate is removed. */
            b.aktiv = 1
            AND (
                (
                    @bevilling_id IS NOT NULL
                    AND (
                        b.bevilling_id = @bevilling_id
                        OR (@target_cpr IS NOT NULL AND b.cpr_elev = @target_cpr)
                    )
                )
                OR
                (
                    @bevilling_id IS NULL
                    AND LOWER(ISNULL(s.status_tekst, '')) NOT IN (N'udløbet', N'udgået')
                )
            )
    ),

    koersel_flags AS (
        SELECT
            tb.*,
            COALESCE(kf.complete_koersel_count, 0) AS complete_koersel_count,
            COALESCE(kf.invalid_date_range_count, 0) AS invalid_date_range_count,
            COALESCE(kf.has_active_koersel, 0) AS has_active_koersel,
            COALESCE(kf.has_future_koersel, 0) AS has_future_koersel,
            COALESCE(kf.has_past_koersel, 0) AS has_past_koersel
        FROM
            target_bevillinger tb
        OUTER APPLY (
            SELECT
                COUNT(*) AS complete_koersel_count,
                SUM(CASE WHEN CONVERT(DATE, k.gyldig_fra) > CONVERT(DATE, k.gyldig_til) THEN 1 ELSE 0 END) AS invalid_date_range_count,
                MAX(CASE WHEN @today BETWEEN CONVERT(DATE, k.gyldig_fra) AND CONVERT(DATE, k.gyldig_til) THEN 1 ELSE 0 END) AS has_active_koersel,
                MAX(CASE WHEN CONVERT(DATE, k.gyldig_fra) > @today THEN 1 ELSE 0 END) AS has_future_koersel,
                MAX(CASE WHEN CONVERT(DATE, k.gyldig_til) < @today THEN 1 ELSE 0 END) AS has_past_koersel
            FROM [befordring].[Koersel] k
            WHERE
                k.bevilling_id = tb.bevilling_id
                /* Same reasoning as Bevilling.aktiv above: a soft-deleted
                   kørselsrække is gone as far as the application is concerned,
                   so it must not contribute has_active_koersel and keep a
                   bevilling looking Aktiv after its only kørsel was removed. */
                AND k.aktiv = 1
                AND k.gyldig_fra IS NOT NULL
                AND k.gyldig_til IS NOT NULL
        ) kf
    ),

    calculated AS (
        SELECT
            kf.bevilling_id,
            kf.current_status_id,
            kf.current_status_text,
            kf.skolekode_mismatch,
            kf.adresse_mismatch,
            kf.stamdata_mangler,
            kf.mangler_skolekode,
            kf.mangler_adresse,
            -- Real status: NO Revurdering branch anymore.
            CASE
                WHEN LOWER(ISNULL(kf.current_status_text, '')) IN (N'afslag', N'ophørt')
                    THEN kf.current_status_text
                WHEN NULLIF(LTRIM(RTRIM(kf.cpr_elev)), '') IS NULL
                    THEN N'Fejlet'
                WHEN kf.complete_koersel_count = 0
                    THEN
                        CASE
                            WHEN kf.sagsbehandler_id IS NOT NULL
                                THEN N'Påbegyndt'
                            ELSE N'Ny'
                        END
                WHEN kf.invalid_date_range_count > 0
                    THEN N'Fejlet'
                WHEN kf.has_active_koersel = 1
                    THEN N'Aktiv'
                WHEN kf.has_future_koersel = 1
                    THEN N'Kommende'
                WHEN kf.has_past_koersel = 1
                    THEN N'Udløbet'
                ELSE N'Fejlet'
            END AS calculated_status_text,
            -- Reassessment flag: date-based only (approaching revurderingsdato).
            -- Mismatch cases (skolekode/adresse) are handled by needs_genbehandling below.
            CASE
                WHEN LOWER(ISNULL(kf.current_status_text, '')) NOT IN (N'afslag', N'ophørt')
                    AND NULLIF(LTRIM(RTRIM(kf.cpr_elev)), '') IS NOT NULL
                    AND kf.complete_koersel_count > 0
                    AND kf.invalid_date_range_count = 0
                    AND (
                        -- entry: date trigger only
                        (
                            kf.has_active_koersel = 1
                            AND ISNULL(kf.revurderet_af_br, 0) = 0
                            AND kf.revurderingsdato IS NOT NULL
                            AND @today >= DATEADD(MONTH, -2, kf.revurderingsdato)
                        )
                        OR
                        -- stay: hold until BR signs off
                        (
                            ISNULL(kf.current_revurdering, 0) = 1
                            AND ISNULL(kf.revurderet_af_br, 0) = 0
                        )
                    )
                THEN 1
                ELSE 0
            END AS needs_revurdering,
            -- Genbehandling flag: drift (skolekode or adresse mismatch) OR
            -- missing stamdata to compare the bevilling against.
            CASE
                WHEN LOWER(ISNULL(kf.current_status_text, '')) NOT IN (N'afslag', N'ophørt')
                    AND NULLIF(LTRIM(RTRIM(kf.cpr_elev)), '') IS NOT NULL
                    AND kf.complete_koersel_count > 0
                    AND kf.invalid_date_range_count = 0
                    AND (
                        -- entry: mismatch detected and not yet acknowledged via snapshot
                        (
                            kf.has_active_koersel = 1
                            AND (
                                (
                                    kf.adresse_mismatch = 1
                                    AND (
                                        kf.genbehandling_haandteret_adresse_id IS NULL
                                        OR kf.elev_adresse_id <> kf.genbehandling_haandteret_adresse_id
                                    )
                                )
                                OR
                                (
                                    kf.skolekode_mismatch = 1
                                    AND (
                                        kf.genbehandling_haandteret_skolekode IS NULL
                                        OR kf.elev_skolekode <> kf.genbehandling_haandteret_skolekode
                                    )
                                )
                                OR
                                /* Missing stamdata, not yet acknowledged.

                                   A BIT rather than a snapshot comparison
                                   like the two above, and that is the whole
                                   design. Those re-flag when the elev value
                                   MOVES AWAY from the one signed off; here
                                   there is no value, so "has it changed since
                                   sign-off" has no answer and a NULL snapshot
                                   would read as "never signed off" forever.
                                   The bevilling would return to the list on
                                   every nightly run, and the only thing that
                                   could stop it is the data that is missing.

                                   genbehandling_haandteret alone cannot carry
                                   this either: the UPDATE below resets it to
                                   NULL whenever needs_genbehandling is still
                                   1 on a signed-off cycle, which is exactly
                                   this situation. The flag has to survive in
                                   a column the entry test itself reads. */
                                (
                                    kf.stamdata_mangler = 1
                                    AND ISNULL(kf.genbehandling_haandteret_stamdata, 0) = 0
                                )
                            )
                        )
                        OR
                        -- stay: hold until caseworker marks it handled, but only while
                        -- a mismatch is still live AND the bevilling has an active kørsel.
                        -- Expired bevillinger auto-close rather than requiring caseworker action.
                        (
                            ISNULL(kf.current_genbehandling, 0) = 1
                            AND ISNULL(kf.genbehandling_haandteret, 0) = 0
                            AND (
                                kf.adresse_mismatch = 1
                                OR kf.skolekode_mismatch = 1
                                OR kf.stamdata_mangler = 1
                            )
                            AND kf.has_active_koersel = 1
                        )
                    )
                THEN 1
                ELSE 0
            END AS needs_genbehandling
        FROM
            koersel_flags kf
    )

    SELECT
        c.bevilling_id,
        c.current_status_id,
        c.current_status_text,
        s.status_id AS calculated_status_id,
        c.calculated_status_text,
        c.needs_revurdering,
        c.needs_genbehandling,
        c.skolekode_mismatch,
        c.adresse_mismatch,
        c.stamdata_mangler,
        c.mangler_skolekode,
        c.mangler_adresse,
        CASE
            WHEN ISNULL(c.current_status_id, -1) <> ISNULL(s.status_id, -1) THEN 1
            ELSE 0
        END AS status_will_change,
        CAST(NULL AS NVARCHAR(500)) AS status_reason,
        CAST(NULL AS NVARCHAR(500)) AS genbehandling_bemaerkning
    INTO
        #calculated_statuses
    FROM
        calculated c
    LEFT JOIN
        [befordring].[Status] s ON s.status_tekst = c.calculated_status_text AND s.aktiv = 1;

    IF EXISTS (SELECT 1 FROM #calculated_statuses WHERE calculated_status_id IS NULL)
    BEGIN
        THROW 50002, 'Calculated status does not exist in Status table.', 1;
    END;

    /*
        Active conflict check.
        Rule: a citizen may not have more than one active bevilling.
        NOTE: reassessment-flagged bevillinger now have the real status Aktiv,
        so they participate in this rule (consistent with "still active").
    */
    ;WITH proposed_statuses AS (
        SELECT b.bevilling_id, b.cpr_elev, cs.calculated_status_text AS proposed_status_text
        FROM [befordring].[Bevilling] b
        INNER JOIN #calculated_statuses cs ON cs.bevilling_id = b.bevilling_id
        WHERE b.aktiv = 1

        UNION ALL

        /* The second branch is the one that mattered: it sweeps in every
           bevilling *not* being recalculated and counts its stored status. With
           no aktiv filter a soft-deleted bevilling whose stored status was still
           'Aktiv' kept counting towards the duplicate rule below, and failed the
           live bevilling it had been replaced by. */
        SELECT b.bevilling_id, b.cpr_elev, s.status_tekst AS proposed_status_text
        FROM [befordring].[Bevilling] b
        INNER JOIN [befordring].[Status] s ON s.status_id = b.status_id
        WHERE b.aktiv = 1
          AND NOT EXISTS (SELECT 1 FROM #calculated_statuses cs WHERE cs.bevilling_id = b.bevilling_id)
    ),
    active_conflicts AS (
        SELECT ps.cpr_elev
        FROM proposed_statuses ps
        WHERE NULLIF(LTRIM(RTRIM(ps.cpr_elev)), '') IS NOT NULL
          AND LOWER(ps.proposed_status_text) = N'aktiv'
        GROUP BY ps.cpr_elev
        HAVING COUNT(*) > 1
    )

    UPDATE cs
    SET
        cs.calculated_status_id   = @fejlet_status_id,
        cs.calculated_status_text = N'Fejlet',
        cs.status_reason          = N'Borgeren har mere end én aktiv bevilling',
        cs.status_will_change     = CASE
                                        WHEN ISNULL(cs.current_status_id, -1) <> ISNULL(@fejlet_status_id, -1) THEN 1
                                        ELSE 0
                                    END
    FROM #calculated_statuses cs
    INNER JOIN [befordring].[Bevilling] b ON b.bevilling_id = cs.bevilling_id
    INNER JOIN active_conflicts ac ON ac.cpr_elev = b.cpr_elev
    WHERE LOWER(cs.calculated_status_text) = N'aktiv';

    -- Do not flag a broken (Fejlet) bevilling as needing reassessment or genbehandling.
    UPDATE #calculated_statuses
    SET needs_revurdering = 0, needs_genbehandling = 0
    WHERE calculated_status_text = N'Fejlet';

    /* Revurdering reason — approaching revurderingsdato.

       Revurdering is date-driven only (see needs_revurdering above); skolekode
       and adresse drift are genbehandling and are written to
       genbehandling_bemaerkning further down.

       Those two mismatches used to be assigned here as well, left over from
       before the split. Because every block is guarded on status_reason IS NULL
       the first one to match claims the column, and the mismatches sat first —
       so a bevilling on the revurdering list *for its date* that also had
       school-code drift showed the genbehandling reason on the revurdering
       page, and its own reason was never written at all. */
    UPDATE cs
    SET cs.status_reason = N'Bevillingen nærmer sig revurderingsdato'
    FROM #calculated_statuses cs
    INNER JOIN [befordring].[Bevilling] b ON b.bevilling_id = cs.bevilling_id
    WHERE
        cs.needs_revurdering = 1
        AND b.revurderingsdato IS NOT NULL
        AND @today >= DATEADD(MONTH, -2, CONVERT(DATE, b.revurderingsdato))
        AND cs.status_reason IS NULL;

    /* Revurdering reason — already under way.

       needs_revurdering has a "stay" branch that holds the flag at 1 until BR
       signs off, which outlives the date window above and survives
       revurderingsdato being changed or cleared. Without this block those rows
       would carry no reason at all, and the card would render a blank space.

       It also distinguishes the two states on the page: waiting to be picked up
       versus waiting for BR. Deliberately last, so it only catches what the
       date block did not. */
    UPDATE cs
    SET cs.status_reason = N'Afventer sagsbehandling af revurdering'
    FROM #calculated_statuses cs
    WHERE
        cs.needs_revurdering = 1
        AND cs.status_reason IS NULL;

    /* Genbehandling reason — skolekode mismatch. */
    UPDATE cs
    SET cs.genbehandling_bemaerkning = N'Skolekode på bevilling matcher ikke elevens aktuelle skolekode'
    FROM #calculated_statuses cs
    WHERE
        cs.skolekode_mismatch = 1
        AND cs.needs_genbehandling = 1
        AND cs.genbehandling_bemaerkning IS NULL;

    /* Genbehandling reason — address mismatch. */
    UPDATE cs
    SET cs.genbehandling_bemaerkning = N'Elevens adresse matcher ikke adressen på bevillingen'
    FROM #calculated_statuses cs
    WHERE
        cs.adresse_mismatch = 1
        AND cs.needs_genbehandling = 1
        AND cs.genbehandling_bemaerkning IS NULL;

    /* Genbehandling reason — stamdata missing.

       After the two mismatch reasons, not before, because every block here is
       guarded on the column still being NULL and the first to match claims
       it. A mismatch is the more specific statement — it names a value that
       is wrong — so where a bevilling has both a live mismatch and a missing
       field on the other dimension, the mismatch is the better sentence to
       put on the card. (The two cannot collide on the SAME dimension: a
       mismatch needs both sides present, a missing flag needs one absent.)

       Split in two so the card says which field to go and find. The combined
       wording is last and catches the rest, including the student with no
       Elev row at all. */
    UPDATE cs
    SET cs.genbehandling_bemaerkning = N'Eleven mangler skolekode i stamdata, så skolen på bevillingen kan ikke sammenholdes'
    FROM #calculated_statuses cs
    WHERE
        cs.mangler_skolekode = 1
        AND cs.mangler_adresse = 0
        AND cs.needs_genbehandling = 1
        AND cs.genbehandling_bemaerkning IS NULL;

    UPDATE cs
    SET cs.genbehandling_bemaerkning = N'Eleven mangler adresse i stamdata, så adressen på bevillingen kan ikke sammenholdes'
    FROM #calculated_statuses cs
    WHERE
        cs.mangler_adresse = 1
        AND cs.mangler_skolekode = 0
        AND cs.needs_genbehandling = 1
        AND cs.genbehandling_bemaerkning IS NULL;

    UPDATE cs
    SET cs.genbehandling_bemaerkning = N'Eleven mangler stamdata, så bevillingen ikke kan sammenholdes med elevens aktuelle oplysninger'
    FROM #calculated_statuses cs
    WHERE
        cs.stamdata_mangler = 1
        AND cs.needs_genbehandling = 1
        AND cs.genbehandling_bemaerkning IS NULL;

    /* Fejlet reason — missing CPR. */
    UPDATE cs
    SET cs.status_reason = N'Bevillingen mangler CPR-nummer'
    FROM #calculated_statuses cs
    INNER JOIN [befordring].[Bevilling] b ON b.bevilling_id = cs.bevilling_id
    WHERE
        cs.calculated_status_text = N'Fejlet'
        AND NULLIF(LTRIM(RTRIM(b.cpr_elev)), '') IS NULL
        AND cs.status_reason IS NULL;

    /* Fejlet reason — invalid koerselsraekke date range. */
    UPDATE cs
    SET cs.status_reason = N'En eller flere kørselsrækker har ugyldig datoperiode'
    FROM #calculated_statuses cs
    WHERE
        cs.calculated_status_text = N'Fejlet'
        AND cs.status_reason IS NULL
        AND EXISTS (
            SELECT 1
            FROM [befordring].[Koersel] k
            WHERE k.bevilling_id = cs.bevilling_id
              /* Must match the koersel_flags filter above, or a deleted row with
                 a bad date range would be given as the reason for a Fejlet that
                 the live rows caused — or worse, for one they did not. */
              AND k.aktiv = 1
              AND k.gyldig_fra IS NOT NULL
              AND k.gyldig_til IS NOT NULL
              AND CONVERT(DATE, k.gyldig_fra) > CONVERT(DATE, k.gyldig_til)
        );

    IF @dry_run = 0
    BEGIN
        UPDATE b
        SET
            b.status_id = cs.calculated_status_id,
            b.revurdering = cs.needs_revurdering,
            b.statusbemaerkning = CASE
                WHEN cs.calculated_status_text = N'Fejlet' THEN cs.status_reason
                WHEN cs.needs_revurdering = 1 THEN cs.status_reason
                ELSE NULL
            END,
            -- Reset PPR/BR sign-off when a NEW reassessment cycle begins
            -- (flag flips 0 -> 1). Reads the OLD b.revurdering value.
            b.revurderet_af_ppr = CASE
                WHEN cs.needs_revurdering = 1 AND ISNULL(b.revurdering, 0) = 0
                    THEN NULL
                ELSE b.revurderet_af_ppr
            END,
            b.revurderet_af_br = CASE
                WHEN cs.needs_revurdering = 1 AND ISNULL(b.revurdering, 0) = 0
                    THEN NULL
                ELSE b.revurderet_af_br
            END,
            b.genbehandling = cs.needs_genbehandling,
            b.genbehandling_bemaerkning = CASE
                WHEN cs.needs_genbehandling = 1 THEN cs.genbehandling_bemaerkning
                ELSE NULL
            END,
            b.genbehandling_haandteret = CASE
                -- New cycle (0→1) or re-entry (signed-off cycle has new drift): reset so
                -- caseworker must re-acknowledge the new mismatch.
                WHEN cs.needs_genbehandling = 1 AND (ISNULL(b.genbehandling, 0) = 0 OR ISNULL(b.genbehandling_haandteret, 0) = 1)
                    THEN NULL
                -- Cycle ending (1→0): clear stale haandteret so it starts NULL next cycle.
                WHEN cs.needs_genbehandling = 0 AND ISNULL(b.genbehandling, 0) = 1
                    THEN NULL
                ELSE b.genbehandling_haandteret
            END,
            -- Reset snapshot columns on new/re-entry; clear per-dimension when mismatch resolves.
            b.genbehandling_haandteret_adresse_id = CASE
                WHEN cs.needs_genbehandling = 1 AND (ISNULL(b.genbehandling, 0) = 0 OR ISNULL(b.genbehandling_haandteret, 0) = 1) THEN NULL
                WHEN cs.adresse_mismatch = 0                                                                                        THEN NULL
                ELSE b.genbehandling_haandteret_adresse_id
            END,
            b.genbehandling_haandteret_skolekode = CASE
                WHEN cs.needs_genbehandling = 1 AND (ISNULL(b.genbehandling, 0) = 0 OR ISNULL(b.genbehandling_haandteret, 0) = 1) THEN NULL
                WHEN cs.skolekode_mismatch = 0                                                                                      THEN NULL
                ELSE b.genbehandling_haandteret_skolekode
            END,
            -- Same two rules as the snapshots above. The second line is what
            -- makes the flag an acknowledgement of a SITUATION rather than a
            -- permanent silence: the moment the stamdata arrives the sign-off
            -- is cleared, so a student whose data goes missing again is
            -- raised again instead of staying quietly acknowledged forever.
            b.genbehandling_haandteret_stamdata = CASE
                WHEN cs.needs_genbehandling = 1 AND (ISNULL(b.genbehandling, 0) = 0 OR ISNULL(b.genbehandling_haandteret, 0) = 1) THEN NULL
                WHEN cs.stamdata_mangler = 0                                                                                        THEN NULL
                ELSE b.genbehandling_haandteret_stamdata
            END,
            b.updated_by = 'status_engine',
            b.updated_at = GETDATE()
        FROM
            [befordring].[Bevilling] b
        INNER JOIN
            #calculated_statuses cs ON cs.bevilling_id = b.bevilling_id
        WHERE
            ISNULL(b.status_id, -1) <> ISNULL(cs.calculated_status_id, -1)
            OR ISNULL(b.revurdering, 0) <> cs.needs_revurdering
            OR ISNULL(b.genbehandling, 0) <> cs.needs_genbehandling
            OR ISNULL(b.statusbemaerkning, N'') <> ISNULL(
                   CASE
                       WHEN cs.calculated_status_text = N'Fejlet' THEN cs.status_reason
                       WHEN cs.needs_revurdering = 1 THEN cs.status_reason
                       ELSE NULL
                   END, N'')
            -- Snapshot columns may need clearing even when nothing else changed.
            OR (cs.adresse_mismatch = 0 AND b.genbehandling_haandteret_adresse_id IS NOT NULL)
            OR (cs.skolekode_mismatch = 0 AND b.genbehandling_haandteret_skolekode IS NOT NULL)
            OR (cs.stamdata_mangler = 0 AND b.genbehandling_haandteret_stamdata IS NOT NULL)
            -- Re-entry: haandteret must reset when a signed-off cycle sees new drift
            -- (genbehandling stays 1 so the genbehandling column comparison won't catch it).
            OR (cs.needs_genbehandling = 1 AND ISNULL(b.genbehandling_haandteret, 0) = 1);
    END;

    SELECT
        bevilling_id,
        current_status_id,
        current_status_text,
        calculated_status_id,
        calculated_status_text,
        needs_revurdering,
        needs_genbehandling,
        skolekode_mismatch,
        adresse_mismatch,
        stamdata_mangler,
        mangler_skolekode,
        mangler_adresse,
        status_will_change,
        status_reason,
        genbehandling_bemaerkning,
        @dry_run AS dry_run
    FROM
        #calculated_statuses
    ORDER BY
        bevilling_id;
END;
GO