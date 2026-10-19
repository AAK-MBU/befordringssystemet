USE [Befordringssystemet]
GO

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

-- Everyone currently receiving kørselsgodtgørelse for an egenbefordring
-- kørselsrække — the monthly list a caseworker messages.
--
-- The recipient lives in one of two columns, and they are mutually exclusive:
--   koerselsgodtgoerelse_modtager_id  -> Part      (øvrig part, added by hand)
--   koerselsgodtgoerelse_modtager_cpr -> Foraelder (legal guardian)
-- so name and CPR are COALESCEd across both sources.
--
-- One row per PERSON, not per kørselsrække: the same parent can receive for two
-- children, or for several rækker on one child, and they only need telling once.
-- The children are aggregated into a single column so the caseworker can still
-- see who each payment concerns.
--
-- "Currently receiving" means the kørselsrække overlaps the INDBERETNINGS-
-- VINDUE, not that it is valid today. The indberetningsformular lets a
-- recipient report the current month and the four before it — five months in
-- all — so a række that ended two months ago still has unreported months a
-- parent is entitled to claim, and they need the link just as much as someone
-- currently being driven.
--
-- The window is therefore "første dag i måneden for fire måneder siden" to
-- "sidste dag i indeværende måned", and a række qualifies if it overlaps that
-- span by so much as a day.

CREATE OR ALTER VIEW [befordring].[view_Koerselsgodtgoerelse_Modtagere]
AS
WITH modtagere AS (
    SELECT
        -- One identity per person regardless of which table they came from.
        -- CPR is the natural key; parter without one fall back to their id so
        -- they are not all collapsed into a single NULL row.
        COALESCE(
            NULLIF(LTRIM(RTRIM(k.koerselsgodtgoerelse_modtager_cpr)), ''),
            NULLIF(LTRIM(RTRIM(p.cpr_nummer)), ''),
            CONCAT('part:', k.koerselsgodtgoerelse_modtager_id)
        )                                                   AS modtager_noegle,

        COALESCE(f.adresseringsnavn, p.fulde_navn)          AS modtager_navn,
        COALESCE(f.cpr_foraelder, p.cpr_nummer)             AS modtager_cpr,

        CASE
            WHEN k.koerselsgodtgoerelse_modtager_cpr IS NOT NULL THEN N'Forælder'
            ELSE N'Øvrig part'
        END                                                 AS modtager_type,

        e.cpr                                               AS cpr_elev,
        e.adresseringsnavn                                  AS elev_navn

    FROM      [befordring].[Koersel]          k
    INNER JOIN [befordring].[Bevilling]       b   ON b.bevilling_id       = k.bevilling_id
    INNER JOIN [befordring].[Befordringstype] bt  ON bt.befordringstype_id = k.befordringstype_id
    LEFT JOIN [befordring].[Elev]             e   ON e.cpr                = b.cpr_elev
    LEFT JOIN [befordring].[Part]             p   ON p.part_id            = k.koerselsgodtgoerelse_modtager_id
    LEFT JOIN [befordring].[Foraelder]        f   ON f.cpr_foraelder      = k.koerselsgodtgoerelse_modtager_cpr

    WHERE
        -- Egenbefordring only. Whitespace stripped because the lookup labels
        -- are not consistent about it ("Egen befordring" vs "Egenbefordring").
        REPLACE(LOWER(bt.befordringstype_tekst), ' ', '') = N'egenbefordring'

        -- A recipient must actually be named.
    AND (k.koerselsgodtgoerelse_modtager_id IS NOT NULL
         OR NULLIF(LTRIM(RTRIM(k.koerselsgodtgoerelse_modtager_cpr)), '') IS NOT NULL)

        -- Soft-deleted rows are not paid out.
    AND k.aktiv = 1
    AND b.aktiv = 1

        -- Overlaps the five-month indberetningsvindue.
        --
        -- Built from the FIRST of the current month rather than from today, so
        -- the span is whole calendar months — the unit the formular reports
        -- in. Subtracting four months from today would otherwise land
        -- mid-month and cut the earliest month short, and on the 31st it would
        -- also have to cope with shorter target months.
        --
        -- The upper bound is the end of the current month, not today: a række
        -- starting later this month covers days the recipient will report for
        -- this period, and sending the link a little early costs nothing while
        -- leaving someone out costs them a payment.
        --
        -- Expiry is handled entirely here. "Udløbet" is a CALCULATED status
        -- this view never looks at, so widening the window is all that is
        -- needed to bring expired bevillinger back in.
    AND k.gyldig_fra <= EOMONTH(GETDATE())
    AND k.gyldig_til >= DATEADD(
            MONTH, -4,
            DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1)
        )

        -- Afslag only. A refused bevilling never granted kørsel, so there is
        -- nothing to report for any month.
        --
        -- Ophørt is deliberately NOT excluded any more: ending a bevilling
        -- stops future kørsel, it does not retract kørsel that already
        -- happened. A bevilling ended in August can still hold unreported June
        -- and July months, and the date window above is what decides whether
        -- those months are still claimable.
    AND NOT EXISTS (
            SELECT 1
            FROM   [befordring].[Status] st
            WHERE  st.status_id = b.status_id
            AND    st.status_tekst = N'Afslag'
        )
),
-- One row per (modtager, elev). Without this a parent with two kørselsrækker
-- for the same child would have that child listed twice: STRING_AGG has no
-- DISTINCT in SQL Server.
pr_elev AS (
    SELECT DISTINCT modtager_noegle, cpr_elev, elev_navn
    FROM   modtagere
)
SELECT
    m.modtager_noegle,
    MAX(m.modtager_navn)          AS modtager_navn,
    MAX(m.modtager_cpr)           AS modtager_cpr,
    MAX(m.modtager_type)          AS modtager_type,

    COUNT(*)                      AS antal_koerselsraekker,
    COUNT(DISTINCT m.cpr_elev)    AS antal_elever,

    -- Which children the payments concern, so one row still carries the context.
    --
    -- Plain ', ' separator, not N', ': Elev.adresseringsnavn is varchar, and
    -- SQL Server rejects an nvarchar separator against a varchar expression
    -- (Msg 8116). Every other view in this folder uses the same form.
    (
        SELECT STRING_AGG(pe.elev_navn, ', ') WITHIN GROUP (ORDER BY pe.elev_navn)
        FROM   pr_elev pe
        WHERE  pe.modtager_noegle = m.modtager_noegle
    )                             AS elever
FROM     modtagere m
GROUP BY m.modtager_noegle;
GO
