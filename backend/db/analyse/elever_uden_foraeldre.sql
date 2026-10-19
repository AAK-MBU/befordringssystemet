/* ============================================================
   Elever med en bevilling, men uden forældremyndighedsindehavere

   Foraelder-tabellen holder barnets forældremyndighedsindehavere, indlæst
   fra stamdata. Står en elev slet ikke i den, har sagen ingen part at sende
   afgørelsen til: forsendelsen bygger modtagerlisten på netop de rækker.

   Afgrænsningen er "eleven har overhovedet en bevilling". IKKE aktiv, ikke
   ikke-slettet, ikke en bestemt status — enhver række i Bevilling tæller.
   Det er bevidst: formålet er at finde elever, hvor indlæsningen af
   forældre af en eller anden grund ikke er sket, og dét er lige så forkert
   på en soft-slettet eller udløbet bevilling som på en aktiv. Soft-delete
   og status står som kolonner i del 1, så de kan sorteres fra bagefter
   frem for at være valgt fra på forhånd.

   Part-tabellen er IKKE et alternativ til Foraelder. Den holder øvrige
   parter, en sagsbehandler tilføjer i hånden — en bedsteforælder, en
   kontaktperson — og den erstatter ikke forældremyndighed. Den tælles med
   i del 1 som oplysning: en elev uden forældre MEN med en part er stadig
   en fejl, bare en hvor nogen allerede har arbejdet udenom.

   Kun læsning. Intet opdateres.
============================================================ */

USE [Befordringssystemet];

SET NOCOUNT ON;


-- ---------------------------------------------------------------------------
-- 1. Eleverne, én række pr. elev
--
--    NOT EXISTS frem for LEFT JOIN ... IS NULL: der er ingen rækker at
--    multiplicere med, så elevlisten bliver entydig uden DISTINCT.
--
--    Bevillingskolonnerne er aggregeret, fordi en elev kan have flere
--    bevillinger og spørgsmålet stilles om ELEVEN, ikke om bevillingen.
-- ---------------------------------------------------------------------------
SELECT
    STUFF(e.cpr, 7, 0, '-')                         AS cpr,

    -- MAX frem for GROUP BY på felterne: adresseringsnavn er varchar(max),
    -- og de er alle entydige pr. elev, da der grupperes på primærnøglen.
    -- Det holder LOB-kolonner ude af GROUP BY-nøglen.
    MAX(e.adresseringsnavn)                         AS adresseringsnavn,
    MAX(CAST(e.navne_adresse_beskyttelse AS tinyint)) AS navne_adresse_beskyttelse,
    MAX(e.skolekode)                                AS skolekode,

    COUNT(b.bevilling_id)                           AS antal_bevillinger,
    SUM(CASE WHEN b.aktiv = 1 THEN 1 ELSE 0 END)    AS heraf_ikke_slettet,

    -- Hvilke statusser eleven har bevillinger i, så en liste kan skimmes
    -- uden at slå hver sag op. Plain ', ' — Status.status_tekst er varchar,
    -- og en nvarchar-separator giver Msg 8116.
    (
        SELECT STRING_AGG(x.status_tekst, ', ') WITHIN GROUP (ORDER BY x.status_tekst)
        FROM (
            SELECT DISTINCT st2.status_tekst
            FROM   [befordring].[Bevilling] b2
            JOIN   [befordring].[Status]    st2 ON st2.status_id = b2.status_id
            WHERE  b2.cpr_elev = e.cpr
        ) x
    )                                               AS statusser,

    MIN(b.created_at)                               AS foerste_bevilling,
    MAX(b.created_at)                               AS seneste_bevilling,

    -- Øvrige parter oprettet i hånden. > 0 betyder at nogen har haft brug
    -- for en modtager og selv har tilføjet én — fejlen er den samme, men
    -- sagen er ikke nødvendigvis gået i stå.
    (
        SELECT COUNT(*)
        FROM   [befordring].[Part] p
        WHERE  p.cpr_elev = e.cpr
        AND    p.aktiv    = 1
    )                                               AS antal_oevrige_parter

FROM       [befordring].[Elev]      e
INNER JOIN [befordring].[Bevilling] b  ON b.cpr_elev = e.cpr
WHERE NOT EXISTS (
        SELECT 1
        FROM   [befordring].[Foraelder] f
        WHERE  f.cpr_elev = e.cpr
      )
GROUP BY
    e.cpr
ORDER BY
    seneste_bevilling DESC;


-- ---------------------------------------------------------------------------
-- 2. Omfang
--
--    Sat op mod totalen, så tallet kan læses som "er det en håndfuld eller
--    er indlæsningen gået i stå".
-- ---------------------------------------------------------------------------
SELECT
    (SELECT COUNT(DISTINCT b.cpr_elev)
     FROM   [befordring].[Bevilling] b)                      AS elever_med_bevilling,

    (SELECT COUNT(DISTINCT b.cpr_elev)
     FROM   [befordring].[Bevilling] b
     WHERE  NOT EXISTS (SELECT 1 FROM [befordring].[Foraelder] f
                        WHERE f.cpr_elev = b.cpr_elev))      AS heraf_uden_foraeldre,

    -- Samme spørgsmål, men kun for sager der stadig lever. Er dette tal 0,
    -- mens tallet ovenfor ikke er det, rammer fejlen kun gammelt data.
    (SELECT COUNT(DISTINCT b.cpr_elev)
     FROM   [befordring].[Bevilling] b
     JOIN   [befordring].[Status]    st ON st.status_id = b.status_id
     WHERE  b.aktiv = 1
     AND    st.status_tekst IN (N'Aktiv', N'Kommende', N'Ny', N'Påbegyndt')
     AND    NOT EXISTS (SELECT 1 FROM [befordring].[Foraelder] f
                        WHERE f.cpr_elev = b.cpr_elev))      AS heraf_paa_levende_sager;


-- ---------------------------------------------------------------------------
-- 3. Findes eleven overhovedet i Elev?
--
--    Del 1 joiner via Elev og viser derfor kun elever, der ER i stamdata.
--    En bevilling kan pege på et CPR, som aldrig er indlæst — da mangler
--    både elev og forældre, og det er en anden fejl med en anden rettelse.
-- ---------------------------------------------------------------------------
SELECT
    STUFF(b.cpr_elev, 7, 0, '-')  AS cpr,
    COUNT(*)                      AS antal_bevillinger,
    MAX(b.created_at)             AS seneste_bevilling
FROM   [befordring].[Bevilling] b
WHERE  NOT EXISTS (SELECT 1 FROM [befordring].[Elev] e WHERE e.cpr = b.cpr_elev)
GROUP BY b.cpr_elev
ORDER BY seneste_bevilling DESC;
