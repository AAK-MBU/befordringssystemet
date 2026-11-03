/* ============================================================
   Aktive og kommende bevillinger, hvor der IKKE er valgt et afgørelsesbrev

   "Ikke valgt" er Bevilling.afgoerelsesbrev_id IS NULL — feltet på sagen,
   som sagsbehandleren sætter. Der findes ingen "ikke valgt"-række i
   Afgoerelsesbrev, så NULL er den eneste måde at stå tom på.

   Det er IKKE det samme som "der er ikke dannet et brev". Brev-tabellen
   har én række pr. dannet brev, og de to kan afvige hver sin vej:

     - afgoerelsesbrev_id udfyldt, ingen Brev-række  -> valgt, aldrig dannet
     - afgoerelsesbrev_id NULL, Brev-række findes    -> dannet, siden ryddet

   Del 2 tæller begge dele, så udtrækket kan skelnes fra det, der nok også
   bliver spurgt om senere. Vil du i stedet have "mangler brev", så er det
   NOT EXISTS mod Brev — ikke denne forespørgsel.

   "Aktive og kommende" er Status.status_tekst IN ('Aktiv', 'Kommende'),
   altså den beregnede sagsstatus fra usp_recalculate_bevilling_status —
   ikke soft-delete-flaget Bevilling.aktiv. Begge er filtreret, men de
   betyder ikke det samme.

   Bemærk at 'Fejlet' IKKE er med. En bevilling med mere end én aktiv
   bevilling på samme CPR får status Fejlet og forsvinder dermed ud af
   dette udtræk, selvom den reelt er aktiv. Del 2 tæller dem for sig.

   Kun læsning.
============================================================ */

USE [Befordringssystemet];

SET NOCOUNT ON;


-- ---------------------------------------------------------------------------
-- 1. Udtrækket — én række pr. bevilling.
--
--    Kørselsperioden er MIN/MAX over bevillingens aktive kørselsrækker, så
--    en bevilling med flere rækker fylder én linje. Står perioden tom, har
--    bevillingen ingen aktive kørselsrækker overhovedet.
-- ---------------------------------------------------------------------------
SELECT
    -- Bindestreg ind, så CPR overlever en kopiering til Excel: uden den
    -- læses 0101101234 som et tal, og det foranstillede nul forsvinder.
    STUFF(e.cpr, 7, 0, '-')         AS cpr,
    e.adresseringsnavn,
    -- Udtrækket ryger i Excel og videre rundt. Står flaget 1, er navn og
    -- adresse beskyttet, og rækken skal behandles derefter.
    e.navne_adresse_beskyttelse,
    e.elevklassetrin,
    e.skolekode                     AS elev_skolekode,

    st.status_tekst                 AS status,
    b.bevilling_id,
    b.loebenummer,
    b.ansoegningstype,
    b.final                         AS bevilling_final,

    COALESCE(sm.matrikel_navn, uu.ungdomsuddannelse_navn) AS skole,
    hj.hjemmel_tekst                AS hjemmel,
    sb.sagsbehandler_tekst          AS sagsbehandler,

    b.ansoegningsdato,
    b.sagsbehandlingsdato,
    b.foerste_koersel_dato,
    b.revurderingsdato,

    k.antal_koerselsraekker,
    k.koersel_fra,
    k.koersel_til,

    -- Et dannet brev uden valgt afgørelsesbrev er ikke umuligt — se
    -- hovedkommentaren. Står der et tal her, er sagen ikke ubehandlet.
    br.antal_breve,
    br.seneste_brev,

    b.esdh_url
FROM       [befordring].[Bevilling]         b
INNER JOIN [befordring].[Elev]              e   ON e.cpr       = b.cpr_elev
INNER JOIN [befordring].[Status]            st  ON st.status_id = b.status_id
LEFT  JOIN [befordring].[Skolematrikel]     sm  ON sm.matrikel_id = b.matrikel_id
LEFT  JOIN [befordring].[Ungdomsuddannelse] uu  ON uu.ungdomsuddannelse_id = b.ungdomsuddannelse_id
LEFT  JOIN [befordring].[Hjemmel]           hj  ON hj.hjemmel_id = b.hjemmel_id
LEFT  JOIN [befordring].[Sagsbehandler]     sb  ON sb.sagsbehandler_id = b.sagsbehandler_id
OUTER APPLY (
    SELECT COUNT(*)          AS antal_koerselsraekker,
           MIN(ko.gyldig_fra) AS koersel_fra,
           MAX(ko.gyldig_til) AS koersel_til
    FROM   [befordring].[Koersel] ko
    WHERE  ko.bevilling_id = b.bevilling_id
      AND  ko.aktiv = 1
) k
OUTER APPLY (
    SELECT COUNT(*)                   AS antal_breve,
           MAX(bv.oprettet_tidspunkt) AS seneste_brev
    FROM   [befordring].[Brev] bv
    WHERE  bv.bevilling_id = b.bevilling_id
      AND  bv.aktiv = 1
) br
WHERE  b.aktiv = 1
  AND  b.afgoerelsesbrev_id IS NULL
  AND  st.status_tekst IN (N'Aktiv', N'Kommende')
ORDER BY st.status_tekst, k.koersel_fra, e.adresseringsnavn, b.loebenummer;


-- ---------------------------------------------------------------------------
-- 2. Kontroltal, så et tomt resultat kan skelnes fra en forkert forespørgsel.
--
--    "heraf_med_dannet_brev" er dem, der trods tomt felt allerede har et
--    brev i Brev-tabellen — de er sandsynligvis ikke det, Befordring leder
--    efter, og kan trækkes fra.
--
--    "fejlet_uden_afgoerelsesbrev" står for sig: de er ikke med i del 1,
--    men er reelt sager uden brev, som ingen ser på dette udtræk.
-- ---------------------------------------------------------------------------
WITH grundlag AS (
    SELECT b.bevilling_id,
           st.status_tekst,
           b.afgoerelsesbrev_id,
           (SELECT COUNT(*) FROM [befordring].[Brev] bv
            WHERE bv.bevilling_id = b.bevilling_id AND bv.aktiv = 1) AS antal_breve
    FROM       [befordring].[Bevilling] b
    INNER JOIN [befordring].[Status]    st ON st.status_id = b.status_id
    WHERE  b.aktiv = 1
)
SELECT
    (SELECT COUNT(*) FROM grundlag
     WHERE status_tekst IN (N'Aktiv', N'Kommende'))
        AS aktive_og_kommende_i_alt,
    (SELECT COUNT(*) FROM grundlag
     WHERE status_tekst IN (N'Aktiv', N'Kommende') AND afgoerelsesbrev_id IS NULL)
        AS uden_afgoerelsesbrev,
    (SELECT COUNT(*) FROM grundlag
     WHERE status_tekst = N'Aktiv' AND afgoerelsesbrev_id IS NULL)
        AS heraf_aktiv,
    (SELECT COUNT(*) FROM grundlag
     WHERE status_tekst = N'Kommende' AND afgoerelsesbrev_id IS NULL)
        AS heraf_kommende,
    (SELECT COUNT(*) FROM grundlag
     WHERE status_tekst IN (N'Aktiv', N'Kommende')
       AND afgoerelsesbrev_id IS NULL AND antal_breve > 0)
        AS heraf_med_dannet_brev,
    (SELECT COUNT(*) FROM grundlag
     WHERE status_tekst IN (N'Aktiv', N'Kommende')
       AND afgoerelsesbrev_id IS NOT NULL AND antal_breve = 0)
        AS valgt_men_intet_brev_dannet,
    (SELECT COUNT(*) FROM grundlag
     WHERE status_tekst = N'Fejlet' AND afgoerelsesbrev_id IS NULL)
        AS fejlet_uden_afgoerelsesbrev;


-- ---------------------------------------------------------------------------
-- 3. Valgt, men peger på et afgørelsesbrev der er slået fra.
--
--    Feltet er udfyldt, så sagen tæller ikke som "ikke valgt" i del 1, men
--    teksten er deaktiveret i opslagstabellen og kan ikke vælges igen.
--    Normalt 0 rækker — er der nogen, skal de rettes manuelt.
-- ---------------------------------------------------------------------------
SELECT
    STUFF(e.cpr, 7, 0, '-')  AS cpr,
    e.adresseringsnavn,
    st.status_tekst          AS status,
    b.bevilling_id,
    b.loebenummer,
    ab.afgoerelsesbrev_id,
    ab.afgoerelsesbrev_tekst
FROM       [befordring].[Bevilling]        b
INNER JOIN [befordring].[Elev]             e  ON e.cpr       = b.cpr_elev
INNER JOIN [befordring].[Status]           st ON st.status_id = b.status_id
INNER JOIN [befordring].[Afgoerelsesbrev]  ab ON ab.afgoerelsesbrev_id = b.afgoerelsesbrev_id
WHERE  b.aktiv = 1
  AND  ab.aktiv = 0
  AND  st.status_tekst IN (N'Aktiv', N'Kommende')
ORDER BY e.adresseringsnavn, b.loebenummer;
