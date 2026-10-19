USE [Befordringssystemet]
GO

/****** Object:  View [befordring].[view_Revurderinger]    Script Date: 03/09/2026 09:07:32 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


/* ---------- view_Revurderinger: filter on the flag ---------- */
CREATE OR ALTER VIEW [befordring].[view_Revurderinger] AS
SELECT
    b.bevilling_id,
    b.cpr_elev,
    ba.adresse_tekst                AS adresse_for_bevilling,
    b.matrikel_id,
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
    COALESCE(sm.matrikel_navn, uu.ungdomsuddannelse_navn)
                                    AS skole_navn,
    -- Sags-id og det opløste link til GO. Revurderingssiden tilbyder at åbne
    -- sagen, før en vurdering godkendes — sagen forsvinder fra siden bagefter,
    -- så linket skal være der mens den stadig kan ses.
    b.esdh_noegle,
    b.esdh_url,
    b.revurderingsdato,
    -- Den sidste dag bevillingen dækker nogen som helst. En bevilling har
    -- ingen slutdato selv — det er kørselsrækkerne, der bærer datoerne, og en
    -- bevilling kan have flere med hver sin periode. Derfor MAX: den dato,
    -- hvor den sidste række udløber, er den dato, hvor bevillingen i praksis
    -- holder op. Det er også den, usp_recalculate_bevilling_status bruger til
    -- at sætte status Udløbet.
    kr.seneste_gyldig_til,
    b.revurderet_af_ppr,
    b.revurderet_af_br,
    b.revurdering,
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
LEFT  JOIN [befordring].[Hjemmel]            h   ON h.hjemmel_id             = b.hjemmel_id
LEFT  JOIN [befordring].[Afgoerelsesbrev]    ab  ON ab.afgoerelsesbrev_id    = b.afgoerelsesbrev_id
LEFT  JOIN [befordring].[PPR_Sagsbehandler]  ppr ON ppr.ppr_sagsbehandler_id = b.ppr_sagsbehandler_id
LEFT  JOIN [befordring].[Sagsbehandler]      sb  ON sb.sagsbehandler_id      = b.sagsbehandler_id
LEFT  JOIN [befordring].[Sagsbehandler]      asb ON asb.sagsbehandler_id     = b.ansvarlig_sagsbehandler_id
LEFT  JOIN [befordring].[PPR_Sagsbehandler]  appr ON appr.ppr_sagsbehandler_id = b.ansvarlig_ppr_sagsbehandler_id
-- OUTER APPLY frem for et JOIN med GROUP BY: rækkerne skal ikke multiplicere
-- bevillingen. Soft-slettede rækker tælles ikke med — ellers kunne en slettet
-- række forlænge udløbsdatoen ud over det, bevillingen reelt dækker. Samme
-- mønster som rangeringen af bevillinger i view_Student_Bevillinger.
OUTER APPLY (
    SELECT MAX(k.gyldig_til) AS seneste_gyldig_til
    FROM   [befordring].[Koersel] k
    WHERE  k.bevilling_id = b.bevilling_id
    AND    k.aktiv        = 1
) kr
-- Soft-deleted bevillinger keep their revurdering flag, so without
-- b.aktiv = 1 a deleted bevilling still appears on the Revurdering page.
WHERE      b.aktiv = 1
AND        b.revurdering = 1;
GO


