/* ============================================================
   Elever med AKTIV eller KOMMENDE bevilling til en skole med FLERE matrikler

   Bestilt af Befordring: "en samlet liste over alle elever, med aktive eller
   kommende bevillinger, der er bevilget til en skole med flere matrikler".
   Baggrunden er en formodning om, at foranstaltningsdata i GO har trukket den
   samme matrikel hver gang, så listen skal bruges til at se OMFANGET og rette
   registreringerne.

   Der findes ingen Skole-tabel. En skole ER en skolekode, og en matrikel er en
   række i Skolematrikel med den kode. "Flere matrikler" betyder derfor:
   bevillingens matrikel peger på en skolekode, der optræder mere end én gang i
   Skolematrikel.

   Værd at vide inden tallene læses: INTET i Befordringssystemet gætter en
   matrikel. usp_sync_elev_matrikel_from_bevilling udleder kun en matrikel, når
   skolekoden peger på præcis én — se elever_uden_matrikel_entydig_skolekode.sql.
   Falder alle bevillinger på en skole alligevel på samme matrikel, er valget
   altså truffet et andet sted end her, hvilket passer med formodningen om GO.

   Tre dele:
     1. Listen — én række pr. bevilling, til Excel.
     2. Pr. skole — fordelingen. Det er her, formodningen kan be- eller
        afkræftes.
     3. Kontroltal.

   Bevillinger til en ungdomsuddannelse er ikke med: de har ingen matrikel_id,
   og Ungdomsuddannelse har ikke matrikler.

   "Aktiv"/"Kommende" er status_tekst, ikke soft-delete-flaget Bevilling.aktiv
   — begge er filtreret, men de betyder ikke det samme.

   Kun læsning.
============================================================ */

USE [Befordringssystemet];

SET NOCOUNT ON;


-- ---------------------------------------------------------------------------
-- 1. Listen. Én række pr. bevilling — en elev med to bevillinger står to
--    gange, for det er bevillingen, der peger på matriklen.
--
--    De tre afstandskolonner er det, der gør listen til mere end en optælling.
--    Både Adresse og Skolematrikel har koordinater, så afstanden fra
--    bevillingens adresse til HVER af skolens matrikler kan regnes ud her.
--    Er en anden matrikel mærkbart tættere på end den bevilgede, er det den
--    stærkeste indikation, vi har på en forkert registrering.
--
--    LÆS DEM SOM EN SORTERING, IKKE SOM EN DOM. Afstanden er i fugleflugt,
--    ikke gåafstand, og en elev kan udmærket høre til på den fjerneste
--    matrikel — det er netop derfor, skoler har flere: årgangene er delt.
--    Kolonnen peger på, hvilke rækker der skal ses efter først.
-- ---------------------------------------------------------------------------
SELECT
    -- Bindestreg ind, så CPR overlever en kopiering til Excel: uden den læses
    -- 0101101234 som et tal, og det foranstillede nul forsvinder. Taget fra
    -- bevillingen, ikke fra Elev, så en bevilling uden elevrække stadig kan
    -- identificeres.
    STUFF(b.cpr_elev, 7, 0, '-')    AS cpr,
    e.adresseringsnavn,
    e.elevklassetrin,

    st.status_tekst                 AS status,
    b.bevilling_id,
    b.loebenummer,

    sm.skolekode,
    m.antal_matrikler,
    sm.matrikel_navn                AS bevilget_matrikel,
    sm.matrikel_adresse             AS bevilget_matrikel_adresse,
    CASE WHEN sm.er_matrikel_hovedadresse = 1 THEN N'Ja' ELSE N'Nej' END
                                    AS er_hovedadresse,

    ad.adresse_tekst                AS elevens_adresse,
    CAST(tildelt.km   AS DECIMAL(6,2)) AS km_til_bevilget,
    naer.matrikel_navn                 AS naermeste_matrikel,
    CAST(naer.km      AS DECIMAL(6,2)) AS km_til_naermeste,
    -- Positiv = den bevilgede matrikel ligger længere væk end en anden af
    -- skolens. Sorteres der på denne, står de mest mistænkelige øverst.
    CAST(tildelt.km - naer.km AS DECIMAL(6,2)) AS forskel_km,

    -- Bevillingens egen gåafstand, til sammenligning. Den er målt til den
    -- BEVILGEDE matrikel, så er den beregnet på et forkert valg, er
    -- afstandskriteriet beregnet på den samme fejl.
    b.gaaafstand_km
FROM        [befordring].[Bevilling]     b
INNER JOIN  [befordring].[Status]        st ON st.status_id   = b.status_id
INNER JOIN  [befordring].[Skolematrikel] sm ON sm.matrikel_id = b.matrikel_id
CROSS APPLY (
    SELECT COUNT(*) AS antal_matrikler
    FROM   [befordring].[Skolematrikel] s
    WHERE  s.skolekode = sm.skolekode
) m
-- LEFT JOIN, ikke INNER: en bevilling uden elevrække skal med på listen frem
-- for at forsvinde fra den. Navn og klassetrin står så tomme.
LEFT  JOIN  [befordring].[Elev]          e  ON e.cpr        = b.cpr_elev
LEFT  JOIN  [befordring].[Adresse]       ad ON ad.adresse_id = b.adresse_id

-- Afstanden til den bevilgede matrikel. Koordinaterne tjekkes, fordi
-- geography::Point KASTER på en breddegrad uden for -90..90 — ét dårligt
-- koordinat ville ellers vælte hele scriptet frem for at give NULL i én række.
CROSS APPLY (VALUES (
    CASE WHEN ad.latitude  BETWEEN  -90 AND  90
         AND  ad.longitude BETWEEN -180 AND 180
         AND  sm.latitude  BETWEEN  -90 AND  90
         AND  sm.longitude BETWEEN -180 AND 180
         THEN geography::Point(ad.latitude, ad.longitude, 4326)
                .STDistance(geography::Point(sm.latitude, sm.longitude, 4326)) / 1000.0
    END
)) AS tildelt(km)

-- Den nærmeste af skolens matrikler, uanset hvilken der er bevilget.
OUTER APPLY (
    SELECT TOP (1)
        alt.matrikel_id,
        alt.matrikel_navn,
        geography::Point(ad.latitude, ad.longitude, 4326)
            .STDistance(geography::Point(alt.latitude, alt.longitude, 4326)) / 1000.0 AS km
    FROM   [befordring].[Skolematrikel] alt
    WHERE  alt.skolekode  = sm.skolekode
    AND    ad.latitude    BETWEEN  -90 AND  90
    AND    ad.longitude   BETWEEN -180 AND 180
    AND    alt.latitude   BETWEEN  -90 AND  90
    AND    alt.longitude  BETWEEN -180 AND 180
    ORDER BY geography::Point(ad.latitude, ad.longitude, 4326)
                .STDistance(geography::Point(alt.latitude, alt.longitude, 4326))
) AS naer

WHERE   b.aktiv = 1
AND     st.status_tekst IN (N'Aktiv', N'Kommende')
AND     m.antal_matrikler > 1
ORDER BY CASE WHEN tildelt.km IS NULL OR naer.km IS NULL THEN 1 ELSE 0 END,
         (tildelt.km - naer.km) DESC,
         sm.skolekode,
         e.adresseringsnavn;


-- ---------------------------------------------------------------------------
-- 2. Pr. skole — fordelingen over matrikler.
--
--    Det er denne del, der svarer på formodningen. "Trak GO den samme matrikel
--    hver gang?" aflæses på antal_matrikler_i_brug: står der 1, hvor skolen har
--    2 eller 3, er alle bevillinger landet samme sted, og så er valget ikke
--    truffet pr. elev. Er de fordelt, er registreringen formentlig sket rigtigt
--    på den skole, og den kan lades være.
--
--    De to sidste kolonner siger HVILKEN matrikel der blev den faste, og det
--    peger på mekanismen: altid hovedadressen ligner et opslag på
--    hovedadresse-flaget, mens altid den laveste matrikel_id ligner "tag den
--    første række".
-- ---------------------------------------------------------------------------
WITH bevillinger AS (
    SELECT
        sm.skolekode,
        b.matrikel_id,
        sm.er_matrikel_hovedadresse
    FROM       [befordring].[Bevilling]     b
    INNER JOIN [befordring].[Status]        st ON st.status_id   = b.status_id
    INNER JOIN [befordring].[Skolematrikel] sm ON sm.matrikel_id = b.matrikel_id
    WHERE  b.aktiv = 1
    AND    st.status_tekst IN (N'Aktiv', N'Kommende')
),
skoler AS (
    SELECT
        s.skolekode,
        COUNT(*)            AS antal_matrikler,
        MIN(s.matrikel_id)  AS laveste_matrikel_id
    FROM     [befordring].[Skolematrikel] s
    GROUP BY s.skolekode
    HAVING   COUNT(*) > 1
)
SELECT
    sk.skolekode,
    sk.antal_matrikler,
    COUNT(bv.matrikel_id)                                  AS antal_bevillinger,
    COUNT(DISTINCT bv.matrikel_id)                         AS antal_matrikler_i_brug,
    CASE WHEN COUNT(DISTINCT bv.matrikel_id) = 1 THEN N'Ja' ELSE N'Nej' END
                                                           AS alle_paa_samme_matrikel,
    CASE WHEN COUNT(DISTINCT bv.matrikel_id) = 1
          AND MIN(CAST(bv.er_matrikel_hovedadresse AS INT)) = 1
         THEN N'Ja' ELSE N'Nej' END                        AS den_faste_er_hovedadressen,
    CASE WHEN COUNT(DISTINCT bv.matrikel_id) = 1
          AND MIN(bv.matrikel_id) = sk.laveste_matrikel_id
         THEN N'Ja' ELSE N'Nej' END                        AS den_faste_er_laveste_id
FROM       skoler      sk
LEFT JOIN  bevillinger bv ON bv.skolekode = sk.skolekode
GROUP BY   sk.skolekode, sk.antal_matrikler, sk.laveste_matrikel_id
HAVING     COUNT(bv.matrikel_id) > 0
ORDER BY   antal_bevillinger DESC, sk.skolekode;


-- ---------------------------------------------------------------------------
-- 3. Kontroltal, så et lille resultat kan skelnes fra en forkert forespørgsel.
--
--    uden_koordinat er rækker, hvor afstandskolonnerne i del 1 står tomme:
--    bevillingens adresse eller en af matriklerne mangler et koordinat. De er
--    ikke frasorteret, men afstanden kan ikke bruges til at vurdere dem.
-- ---------------------------------------------------------------------------
SELECT
    (SELECT COUNT(*) FROM (
        SELECT s.skolekode FROM [befordring].[Skolematrikel] s
        GROUP BY s.skolekode HAVING COUNT(*) > 1) x)
        AS skoler_med_flere_matrikler,
    (SELECT COUNT(*)
     FROM       [befordring].[Bevilling] b
     INNER JOIN [befordring].[Status]    st ON st.status_id = b.status_id
     WHERE  b.aktiv = 1 AND st.status_tekst IN (N'Aktiv', N'Kommende'))
        AS aktive_og_kommende_i_alt,
    (SELECT COUNT(*)
     FROM       [befordring].[Bevilling]     b
     INNER JOIN [befordring].[Status]        st ON st.status_id   = b.status_id
     INNER JOIN [befordring].[Skolematrikel] sm ON sm.matrikel_id = b.matrikel_id
     CROSS APPLY (SELECT COUNT(*) AS n FROM [befordring].[Skolematrikel] s
                  WHERE s.skolekode = sm.skolekode) m
     WHERE  b.aktiv = 1 AND st.status_tekst IN (N'Aktiv', N'Kommende') AND m.n > 1)
        AS heraf_paa_skole_med_flere_matrikler,
    (SELECT COUNT(*)
     FROM       [befordring].[Bevilling]     b
     INNER JOIN [befordring].[Status]        st ON st.status_id   = b.status_id
     INNER JOIN [befordring].[Skolematrikel] sm ON sm.matrikel_id = b.matrikel_id
     CROSS APPLY (SELECT COUNT(*) AS n FROM [befordring].[Skolematrikel] s
                  WHERE s.skolekode = sm.skolekode) m
     LEFT  JOIN [befordring].[Adresse]       ad ON ad.adresse_id  = b.adresse_id
     WHERE  b.aktiv = 1 AND st.status_tekst IN (N'Aktiv', N'Kommende') AND m.n > 1
       AND (ad.latitude IS NULL OR sm.latitude IS NULL))
        AS uden_koordinat,
    (SELECT COUNT(*)
     FROM       [befordring].[Bevilling] b
     INNER JOIN [befordring].[Status]    st ON st.status_id = b.status_id
     WHERE  b.aktiv = 1 AND st.status_tekst IN (N'Aktiv', N'Kommende')
       AND  b.matrikel_id IS NULL)
        AS udeladt_ungdomsuddannelse;
