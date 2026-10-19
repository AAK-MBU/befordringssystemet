USE [Befordringssystemet]
GO


/* ---------- view_Genbehandling: bevillinger flagged for genbehandling ----------
   Triggered by data mismatches (skolekode or adresse) between the bevilling
   and the student's current CPR data. Separate from the date-driven Revurdering
   page. Sign-off is a single flag (genbehandling_haandteret) rather than the
   two-step PPR/BR flow used for revurdering.
*/
CREATE OR ALTER VIEW [befordring].[view_Genbehandling] AS
SELECT
    b.bevilling_id,
    b.cpr_elev,
    b.ansoegningstype,
    ba.adresse_tekst                AS adresse_for_bevilling,
    b.matrikel_id,
    b.ungdomsuddannelse_id,
    e.adresseringsnavn,
    a.adresse_tekst                 AS folkeregister_adresse,
    e.skoleafstand                  AS gaaafstand_km,
    -- Skolekoden, ikke bare skolens navn. Elevdata-panelet på Revurderings- og
    -- Genbehandlingssiden viser den, så panelet kan vise det samme som elevens
    -- stamdatakort — og på genbehandling er netop skolekoden tit grunden til,
    -- at sagen står på listen.
    e.skolekode,
    -- Institution og bopælsdistrikt hører til elevens stamdata og vises i
    -- Elevoplysninger-komponenten, som Revurderings- og Genbehandlingssiden
    -- deler med elevens egen side. Står de ikke her, er panelet en delmængde
    -- af kortet — og så er de tre udgaver drevet fra hinanden igen.
    -- Sags-id og det opløste link til GO, så Elevoplysninger kan vise Sags-ID
    -- som hyperlink her ligesom på elevens egen side. view_Revurderinger har
    -- dem i forvejen.
    b.esdh_noegle,
    b.esdh_url,
    e.institution,
    e.bopaelsdistrikt,
    e.klasseart,
    e.elevklassetrin,
    e.klassebetegnelse,
    -- Elevens INDSKREVNE skole — e.matrikel_id, ikke b.matrikel_id. De to er
    -- tit forskellige: en bevilling bærer den skole, afgørelsen blev truffet
    -- på, og en elev, der er flyttet eller visiteret videre, står indskrevet
    -- et andet sted. PPR forbereder revurderinger ude på skolerne og skal
    -- bruge den skole, eleven faktisk går på.
    --
    -- Det er også den samme kolonne, Elevoplysninger-komponenten læser, og
    -- view_Stamdata har altid slået den op på e.matrikel_id. Indtil nu sagde
    -- disse to views b.matrikel_id, så "Elevdata" viste bevillingens skole.
    --
    -- Bevillingens egen skole er uændret tilgængelig: b.matrikel_id står
    -- ovenfor, og den udfoldede Bevillinger-sektion henter navnet fra
    -- view_Student_Bevillinger, som joiner på netop b.matrikel_id.
    -- Tredje udvej: skolekoden. Elev.matrikel_id udledes af
    -- usp_sync_elev_matrikel_from_bevilling, og den nægter med vilje at udlede
    -- noget, når bevillingens matrikel ikke hører til elevens skolekode. Det er
    -- den rigtige regel, men den efterlader feltet TOMT på netop de elever,
    -- sagsbehandlerne kigger på her — og de skal kunne se, hvilken skole
    -- eleven er indskrevet på, uanset om bevillingen stemmer.
    --
    -- Skolekoden ER indskrivningen, så den kan slås op direkte. Navnet herfra
    -- siger intet om bevillingen; den uoverensstemmelse står stadig på
    -- genbehandlingssiden som det, den er.
    COALESCE(sm.matrikel_navn, uu.ungdomsuddannelse_navn, sk.skole_navn)
                                    AS skole_navn,
    b.revurderingsdato,
    b.genbehandling,
    b.genbehandling_haandteret,
    b.genbehandling_bemaerkning,
    b.afstandskriterie_dato,
    b.hjemmel_id,
    h.hjemmel_tekst,
    b.afgoerelsesbrev_id,
    ab.afgoerelsesbrev_tekst,
    b.ppr_sagsbehandler_id,
    ppr.ppr_sagsbehandler_tekst,
    b.sagsbehandler_id,
    sb.sagsbehandler_tekst,
    -- Hvem der har den ventende opgave LIGE NU, modsat de to felter ovenfor,
    -- som siger hvem der behandlede selve bevillingen. NULL betyder, at ingen
    -- har taget sagen endnu — og det er netop det, listen skal kunne vise.
    -- Se migration 034.
    b.ansvarlig_sagsbehandler_id,
    asb.sagsbehandler_tekst         AS ansvarlig_sagsbehandler_tekst,
    b.ansvarlig_ppr_sagsbehandler_id,
    appr.ppr_sagsbehandler_tekst    AS ansvarlig_ppr_sagsbehandler_tekst,
    s.status_tekst,
    b.statusbemaerkning
FROM       [befordring].[Bevilling]          b
INNER JOIN [befordring].[Status]             s   ON s.status_id              = b.status_id
INNER JOIN [befordring].[Elev]               e   ON e.cpr                    = b.cpr_elev
INNER JOIN [befordring].[Adresse]            a   ON a.adresse_id             = e.adresse_id
LEFT  JOIN [befordring].[Adresse]            ba  ON ba.adresse_id            = b.adresse_id
LEFT  JOIN [befordring].[Skolematrikel]      sm  ON sm.matrikel_id           = e.matrikel_id
LEFT  JOIN [befordring].[Ungdomsuddannelse]  uu  ON uu.ungdomsuddannelse_id  = e.ungdomsuddannelse_id
-- Skolen slået op på elevens skolekode, til når matrikel_id ikke er udledt.
--
-- KUN SKOLENAVNET, ikke matriklens. Matrikler, der deler skolekode, deler
-- navnet før parentesen og adskiller sig kun på afdelingen:
--
--     751020  Kaløvigskolen (Bredevej)
--             Kaløvigskolen (Sanatorievej)
--             Kaløvigskolen (Skovager)
--
-- Skolekoden siger, hvilken SKOLE eleven er indskrevet på — ikke hvilken
-- matrikel. At vælge én af dem ville sætte en afdeling på eleven, som ingen
-- har registreret, og det er værre end et tomt felt. Parentesen klippes væk,
-- så der står "Kaløvigskolen".
--
-- Plus '(' i CHARINDEX, så et navn HELT uden parentes også rammes: uden
-- halen giver CHARINDEX 0, og LEFT(..., -1) fejler.
--
-- OUTER APPLY med TOP 1 frem for et JOIN: et almindeligt JOIN ville gange
-- bevillingsrækken op med antallet af matrikler. Hovedadressen først og
-- matrikel_id som tiebreak, så svaret er det samme hver gang — selv hvis to
-- matrikler mod forventning klipper ned til hver sit navn.
--
-- Elev.skolekode defaulter til 0 (se DF_Elev_Skolekode), og 0 betyder "ingen"
-- — uden NULLIF ville en matrikel med skolekode 0 blive hæftet på alle dem.
OUTER APPLY (
    SELECT TOP 1
           RTRIM(LEFT(sk2.matrikel_navn,
                      CHARINDEX('(', sk2.matrikel_navn + '(') - 1)) AS skole_navn
    FROM   [befordring].[Skolematrikel] sk2
    WHERE  sk2.skolekode = NULLIF(e.skolekode, 0)
    ORDER BY sk2.er_matrikel_hovedadresse DESC, sk2.matrikel_id
) sk
LEFT  JOIN [befordring].[Hjemmel]            h   ON h.hjemmel_id             = b.hjemmel_id
LEFT  JOIN [befordring].[Afgoerelsesbrev]    ab  ON ab.afgoerelsesbrev_id    = b.afgoerelsesbrev_id
LEFT  JOIN [befordring].[PPR_Sagsbehandler]  ppr ON ppr.ppr_sagsbehandler_id = b.ppr_sagsbehandler_id
LEFT  JOIN [befordring].[Sagsbehandler]      sb  ON sb.sagsbehandler_id      = b.sagsbehandler_id
LEFT  JOIN [befordring].[Sagsbehandler]      asb ON asb.sagsbehandler_id     = b.ansvarlig_sagsbehandler_id
LEFT  JOIN [befordring].[PPR_Sagsbehandler]  appr ON appr.ppr_sagsbehandler_id = b.ansvarlig_ppr_sagsbehandler_id
WHERE      b.aktiv = 1
AND        b.genbehandling = 1;
GO