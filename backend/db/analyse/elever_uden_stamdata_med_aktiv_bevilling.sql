/* ============================================================
   Elever med aktiv eller kommende bevilling, men uden stamdata

   Sagen ser tom ud i portalen: folkeregisteradresse, skolekode, skole,
   gåafstand, klassetrin, institution og bopælsdistrikt står alle som "—"
   eller "ikke defineret", mens bevillingen kører.

   Hvorfor ingen af de eksisterende lister fanger dem:

     * GENBEHANDLING fanger kun DRIFT, ikke fravær. Begge mismatch-udtryk i
       usp_recalculate_bevilling_status kræver data i begge ender:
       skolekode kræver ISNULL(e.skolekode, 0) <> 0, adresse kræver
       e.adresse_id IS NOT NULL. Står elevens felt tomt, er udtrykket 0, og
       bevillingen får aldrig genbehandling. Det er med vilje — ellers ville
       hver elev, hvis indlæsning endnu ikke er landet, fylde siden.

     * elever_uden_matrikel_med_aktiv_bevilling.sql udelader dem eksplicit:
       den kræver e.skolekode IS NOT NULL AND e.skolekode <> 0. De tælles
       kun som udeladt_uden_skolekode i dens del 3.

     * usp_sync_elev_matrikel_from_bevilling kan ikke redde dem via
       folkeskole-vejen: den kræver ISNULL(e.skolekode, 0) <> 0 og
       sm.skolekode = e.skolekode, altså en skolekode at krydstjekke imod.
       Uden skolekode kvalificerer bevillingens matrikel aldrig, og
       Elev.matrikel_id bliver stående tom uanset hvor mange gange den
       kører. Ungdomsuddannelses-vejen (b.matrikel_id NULL og
       b.ungdomsuddannelse_id udfyldt) har ikke det krav og virker fint.

   Det er derfor del 3 står for sig: folkeskole-eleverne uden skolekode er
   dem, der er låst fast, og som ikke bliver rettet af et natligt kørsel.

   Elev-rækken kan også mangle helt — LEFT JOIN, så de kommer med, og
   elev_findes viser hvilken slags det er.

   "Aktive og kommende" er Status.status_tekst, ikke soft-delete-flaget
   Bevilling.aktiv.

   Kun læsning.
============================================================ */

USE [Befordringssystemet];

SET NOCOUNT ON;


-- ---------------------------------------------------------------------------
-- 1. Listen — én række pr. bevilling.
--
--    bevilling_* kolonnerne er det, sagen ved, og eleven ikke gør. Er de
--    udfyldt, mens elevens står tomme, findes oplysningen allerede i huset
--    og skal bare den rigtige vej.
-- ---------------------------------------------------------------------------
SELECT
    -- Bindestreg ind, så CPR overlever en kopiering til Excel.
    STUFF(b.cpr_elev, 7, 0, '-')                      AS cpr,
    CASE WHEN e.cpr IS NULL THEN 0 ELSE 1 END         AS elev_findes,
    e.adresseringsnavn,
    e.navne_adresse_beskyttelse,

    st.status_tekst                                   AS status,
    b.bevilling_id,
    b.loebenummer,
    b.ansoegningstype,
    ISNULL(b.genbehandling, 0)                        AS genbehandling,

    -- Hvad eleven mangler. Sortér på antal_tomme_kernefelter for at tage de
    -- værste først.
    CASE WHEN e.adresse_id IS NULL                        THEN 1 ELSE 0 END AS mangler_adresse,
    CASE WHEN ISNULL(e.skolekode, 0) = 0                  THEN 1 ELSE 0 END AS mangler_skolekode,
    CASE WHEN e.matrikel_id IS NULL
          AND e.ungdomsuddannelse_id IS NULL              THEN 1 ELSE 0 END AS mangler_skole,
    CASE WHEN ISNULL(e.elevklassetrin, '') = ''           THEN 1 ELSE 0 END AS mangler_klassetrin,
    CASE WHEN ISNULL(e.institution, '') = ''              THEN 1 ELSE 0 END AS mangler_institution,
    CASE WHEN ISNULL(e.bopaelsdistrikt, '') = ''          THEN 1 ELSE 0 END AS mangler_distrikt,
    (CASE WHEN e.adresse_id IS NULL THEN 1 ELSE 0 END
   + CASE WHEN ISNULL(e.skolekode, 0) = 0 THEN 1 ELSE 0 END
   + CASE WHEN e.matrikel_id IS NULL AND e.ungdomsuddannelse_id IS NULL
          THEN 1 ELSE 0 END)                             AS antal_tomme_kernefelter,

    -- Elevens egne værdier, så en delvis udfyldt række kan ses som delvis.
    e.skolekode                                       AS elev_skolekode,
    e.matrikel_id                                     AS elev_matrikel_id,
    e.ungdomsuddannelse_id                            AS elev_ungdomsuddannelse_id,
    e.adresse_id                                      AS elev_adresse_id,
    e.skoleafstand,
    e.kraever_genberegning,

    -- Det sagen ved.
    b.matrikel_id                                     AS bevilling_matrikel_id,
    b.ungdomsuddannelse_id                            AS bevilling_ungdomsuddannelse_id,
    b.adresse_id                                      AS bevilling_adresse_id,
    COALESCE(sm.matrikel_navn, uu.ungdomsuddannelse_navn) AS bevilling_skole,
    sm.skolekode                                      AS bevilling_skolekode,

    -- Hvilken vej bevillingen kom ind ad. Elev-rækker oprettet gennem
    -- API'et (citizen_service.create_elev) får tomme standardværdier og
    -- bliver aldrig fyldt ud, hvis eleven ikke er med i STG-indlæsningen.
    b.created_by,
    b.created_at,
    b.esdh_url
FROM       [befordring].[Bevilling]         b
INNER JOIN [befordring].[Status]            st ON st.status_id = b.status_id
LEFT  JOIN [befordring].[Elev]              e  ON e.cpr = b.cpr_elev
LEFT  JOIN [befordring].[Skolematrikel]     sm ON sm.matrikel_id = b.matrikel_id
LEFT  JOIN [befordring].[Ungdomsuddannelse] uu ON uu.ungdomsuddannelse_id = b.ungdomsuddannelse_id
WHERE  b.aktiv = 1
  AND  st.status_tekst IN (N'Aktiv', N'Kommende')
  AND  (
           e.cpr IS NULL
        OR e.adresse_id IS NULL
        OR (e.matrikel_id IS NULL AND e.ungdomsuddannelse_id IS NULL)
       )
ORDER BY antal_tomme_kernefelter DESC, st.status_tekst, b.created_at DESC;


-- ---------------------------------------------------------------------------
-- 2. Hvor mange, og hvor kom de fra.
--
--    Svarer på, om det er én elev eller halvtreds, og om de alle er kommet
--    ind ad samme vej. Er created_by den samme for dem alle, er det den
--    vej, der skal rettes — ikke de enkelte sager.
-- ---------------------------------------------------------------------------
WITH ramte AS (
    SELECT b.bevilling_id,
           b.cpr_elev,
           b.created_by,
           st.status_tekst,
           CASE WHEN e.cpr IS NULL THEN 0 ELSE 1 END AS elev_findes,
           CASE WHEN e.adresse_id IS NULL THEN 1 ELSE 0 END AS mangler_adresse,
           CASE WHEN ISNULL(e.skolekode, 0) = 0 THEN 1 ELSE 0 END AS mangler_skolekode,
           CASE WHEN e.matrikel_id IS NULL AND e.ungdomsuddannelse_id IS NULL
                THEN 1 ELSE 0 END AS mangler_skole
    FROM       [befordring].[Bevilling] b
    INNER JOIN [befordring].[Status]    st ON st.status_id = b.status_id
    LEFT  JOIN [befordring].[Elev]      e  ON e.cpr = b.cpr_elev
    WHERE  b.aktiv = 1
      AND  st.status_tekst IN (N'Aktiv', N'Kommende')
      AND  (
               e.cpr IS NULL
            OR e.adresse_id IS NULL
            OR (e.matrikel_id IS NULL AND e.ungdomsuddannelse_id IS NULL)
           )
)
SELECT
    created_by,
    status_tekst                                   AS status,
    COUNT(*)                                       AS antal_bevillinger,
    COUNT(DISTINCT cpr_elev)                       AS antal_elever,
    SUM(CASE WHEN elev_findes = 0 THEN 1 ELSE 0 END) AS elev_raekke_mangler_helt,
    SUM(mangler_adresse)                           AS mangler_adresse,
    SUM(mangler_skolekode)                         AS mangler_skolekode,
    SUM(mangler_skole)                             AS mangler_skole
FROM     ramte
GROUP BY created_by, status_tekst
ORDER BY antal_bevillinger DESC, created_by;


-- ---------------------------------------------------------------------------
-- 3. De låste: folkeskolesager, hvor bevillingen HAR en matrikel, men
--    eleven ingen skolekode har.
--
--    usp_sync_elev_matrikel_from_bevilling kan ikke kopiere matriklen over,
--    fordi folkeskole-vejen kræver sm.skolekode = e.skolekode, og der er
--    ingen skolekode at sammenligne med. Den kører hver nat uden at ændre
--    noget. Rettelsen er at få en skolekode på eleven — enten gennem
--    indlæsningen eller manuelt — hvorefter synkroniseringen selv tager
--    resten.
--
--    Ungdomsuddannelsessager står IKKE her: deres vej har ikke det krav.
-- ---------------------------------------------------------------------------
SELECT
    STUFF(b.cpr_elev, 7, 0, '-')  AS cpr,
    e.adresseringsnavn,
    st.status_tekst               AS status,
    b.bevilling_id,
    b.loebenummer,
    b.matrikel_id                 AS bevilling_matrikel_id,
    sm.matrikel_navn              AS bevilling_skole,
    sm.skolekode                  AS bevilling_skolekode,
    e.skolekode                   AS elev_skolekode,
    e.matrikel_id                 AS elev_matrikel_id,
    b.created_by,
    b.created_at
FROM       [befordring].[Bevilling]     b
INNER JOIN [befordring].[Status]        st ON st.status_id = b.status_id
INNER JOIN [befordring].[Elev]          e  ON e.cpr = b.cpr_elev
INNER JOIN [befordring].[Skolematrikel] sm ON sm.matrikel_id = b.matrikel_id
WHERE  b.aktiv = 1
  AND  st.status_tekst IN (N'Aktiv', N'Kommende')
  AND  ISNULL(e.skolekode, 0) = 0
  AND  e.matrikel_id IS NULL
ORDER BY b.created_at DESC;
