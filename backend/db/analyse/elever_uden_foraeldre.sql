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

   Afgrænset til elever UNDER 18. En myndig elev har ingen
   forældremyndighedsindehavere at mangle — Foraelder står tom, fordi
   forældremyndigheden er ophørt, ikke fordi indlæsningen svigtede — og de
   fyldte ellers listen med rækker, der aldrig skal rettes. Alderen regnes
   ud af CPR, ikke af en kolonne: Elev har ingen fødselsdato.

   Kun læsning. Intet opdateres.
============================================================ */

USE [Befordringssystemet];

SET NOCOUNT ON;

DROP TABLE IF EXISTS #under_18;


-- ---------------------------------------------------------------------------
-- 0. Hvem er under 18
--
--    Alder udledt af CPR. Elev.cpr er ti cifre uden bindestreg: DDMMYY +
--    løbenummer. Århundredet ligger IKKE i årstallet, men i det 7. ciffer
--    sammen med YY — en fast regel fra CPR-kontoret, ikke et skøn:
--
--        7. ciffer 0-3                -> 1900-1999
--        7. ciffer 4 eller 9, YY<=36  -> 2000-2036,  ellers 1937-1999
--        7. ciffer 5-8,       YY<=57  -> 2000-2057,  ellers 1858-1899
--
--    Samme regel som i elever_med_ukendt_skolekode.sql, skrevet helt ud af
--    samme grund: uden den læses et barn født i 2015 ('150315-4xxx') som
--    født i 1915 og ryger ud af ethvert aldersfilter. Den halve regel er
--    den slags, der ser rigtig ud og tier, når den er forkert.
--
--    Bygget på cpr_elev fra Bevilling frem for på Elev, fordi del 3 spørger
--    om netop de CPR-numre, der IKKE har en elevrække.
--
--    Et cpr, der ikke er ti cifre eller ikke danner en gyldig dato, får
--    foedselsdato = NULL og BLIVER STÅENDE. Det er med vilje: at det ikke
--    kan læses, er ikke det samme som at eleven er myndig, og at smide
--    rækken ud ville skjule en manglende forælder bag en tastefejl. Del 2
--    tæller dem, så de ikke forsvinder i stilhed.
-- ---------------------------------------------------------------------------
DECLARE @myndig_graense date = DATEADD(YEAR, -18, CAST(GETDATE() AS date));

SELECT
    b.cpr_elev          AS cpr,
    a.foedselsdato,
    CASE WHEN a.foedselsdato IS NULL THEN NULL ELSE
        DATEDIFF(YEAR, a.foedselsdato, GETDATE())
        - CASE WHEN DATEADD(YEAR, DATEDIFF(YEAR, a.foedselsdato, GETDATE()), a.foedselsdato)
                    > CAST(GETDATE() AS date)
               THEN 1 ELSE 0 END
    END                 AS alder
INTO   #under_18
FROM   (SELECT DISTINCT cpr_elev FROM [befordring].[Bevilling]) b
CROSS APPLY (
    SELECT CASE
        WHEN b.cpr_elev IS NULL OR LEN(b.cpr_elev) <> 10 OR b.cpr_elev LIKE '%[^0-9]%' THEN NULL
        ELSE TRY_CONVERT(date, CONCAT(
            CASE
                WHEN SUBSTRING(b.cpr_elev, 7, 1) IN ('0','1','2','3') THEN 1900
                WHEN SUBSTRING(b.cpr_elev, 7, 1) IN ('4','9')
                     THEN CASE WHEN CAST(SUBSTRING(b.cpr_elev, 5, 2) AS int) <= 36 THEN 2000 ELSE 1900 END
                ELSE CASE WHEN CAST(SUBSTRING(b.cpr_elev, 5, 2) AS int) <= 57 THEN 2000 ELSE 1800 END
            END + CAST(SUBSTRING(b.cpr_elev, 5, 2) AS int),
            '-', SUBSTRING(b.cpr_elev, 3, 2),
            '-', SUBSTRING(b.cpr_elev, 1, 2)
        ))
    END AS foedselsdato
) a
-- Fylder eleven 18 i dag, er vedkommende myndig og falder ud: datoen skal
-- være SENERE end skæringen, ikke lig med den.
WHERE  a.foedselsdato IS NULL
   OR  a.foedselsdato > @myndig_graense;


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

    u.foedselsdato,
    u.alder,                                        -- NULL = cpr kunne ikke læses

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
INNER JOIN #under_18                u  ON u.cpr      = e.cpr
WHERE NOT EXISTS (
        SELECT 1
        FROM   [befordring].[Foraelder] f
        WHERE  f.cpr_elev = e.cpr
      )
GROUP BY
    -- foedselsdato og alder er entydige pr. cpr og kommer fra #under_18,
    -- så de kan stå i nøglen frem for at skulle pakkes ind i MAX().
    e.cpr, u.foedselsdato, u.alder
ORDER BY
    seneste_bevilling DESC;


-- ---------------------------------------------------------------------------
-- 2. Omfang
--
--    Sat op mod totalen, så tallet kan læses som "er det en håndfuld eller
--    er indlæsningen gået i stå".
--
--    Alle tal er afgrænset til under 18 ligesom del 1 — ellers ville
--    omfanget ikke beskrive den liste, det står under. elever_i_alt er
--    uafgrænset og står først, så det kan ses, hvor meget aldersgrænsen
--    skærer fra.
-- ---------------------------------------------------------------------------
SELECT
    (SELECT COUNT(DISTINCT b.cpr_elev)
     FROM   [befordring].[Bevilling] b)                      AS elever_i_alt,

    (SELECT COUNT(*) FROM #under_18)                         AS heraf_under_18,

    (SELECT COUNT(DISTINCT b.cpr_elev)
     FROM   [befordring].[Bevilling] b
     JOIN   #under_18 u ON u.cpr = b.cpr_elev
     WHERE  NOT EXISTS (SELECT 1 FROM [befordring].[Foraelder] f
                        WHERE f.cpr_elev = b.cpr_elev))      AS heraf_uden_foraeldre,

    -- Samme spørgsmål, men kun for sager der stadig lever. Er dette tal 0,
    -- mens tallet ovenfor ikke er det, rammer fejlen kun gammelt data.
    (SELECT COUNT(DISTINCT b.cpr_elev)
     FROM   [befordring].[Bevilling] b
     JOIN   #under_18 u ON u.cpr = b.cpr_elev
     JOIN   [befordring].[Status]    st ON st.status_id = b.status_id
     WHERE  b.aktiv = 1
     AND    st.status_tekst IN (N'Aktiv', N'Kommende', N'Ny', N'Påbegyndt')
     AND    NOT EXISTS (SELECT 1 FROM [befordring].[Foraelder] f
                        WHERE f.cpr_elev = b.cpr_elev))      AS heraf_paa_levende_sager,

    -- Rækker hvor cpr ikke kunne læses som en dato. De er TAGET MED i alle
    -- tallene ovenfor, fordi et ulæseligt cpr ikke gør eleven myndig. Er
    -- dette tal stort, er aldersgrænsen tilsvarende mindre skarp.
    (SELECT COUNT(*) FROM #under_18 WHERE foedselsdato IS NULL)
                                                             AS heraf_ulaeseligt_cpr;


-- ---------------------------------------------------------------------------
-- 3. Findes eleven overhovedet i Elev?
--
--    Del 1 joiner via Elev og viser derfor kun elever, der ER i stamdata.
--    En bevilling kan pege på et CPR, som aldrig er indlæst — da mangler
--    både elev og forældre, og det er en anden fejl med en anden rettelse.
-- ---------------------------------------------------------------------------
SELECT
    STUFF(b.cpr_elev, 7, 0, '-')  AS cpr,
    u.foedselsdato,
    u.alder,
    COUNT(*)                      AS antal_bevillinger,
    MAX(b.created_at)             AS seneste_bevilling
FROM       [befordring].[Bevilling] b
INNER JOIN #under_18 u ON u.cpr = b.cpr_elev
WHERE  NOT EXISTS (SELECT 1 FROM [befordring].[Elev] e WHERE e.cpr = b.cpr_elev)
GROUP BY b.cpr_elev, u.foedselsdato, u.alder
ORDER BY seneste_bevilling DESC;


DROP TABLE IF EXISTS #under_18;
