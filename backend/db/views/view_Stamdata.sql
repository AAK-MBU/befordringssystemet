USE [Befordringssystemet]
GO

/****** Object:  View [befordring].[view_Stamdata]    Script Date: 03/09/2026 09:07:57 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER VIEW [befordring].[view_Stamdata]
AS

WITH PrioritizedBevilling AS (
    SELECT
        b.*,
        st.status_tekst,
        ROW_NUMBER() OVER (
            PARTITION BY b.cpr_elev
            ORDER BY
                -- Statusrangering, ikke bare "er den Aktiv". Den afgør hvilken
                -- bevilling der taler for eleven: det er dens status, eleven
                -- står med på Overblik og på sin egen side.
                --
                -- FEJLET rangerer ØVERST, over Aktiv. En fejlet bevilling kan
                -- ikke bruges. usp_recalculate_bevilling_status sætter den af
                -- tre grunde: borgeren har mere end én aktiv bevilling, en
                -- kørselsrække har gyldig_fra efter gyldig_til, eller
                -- bevillingen mangler CPR.
                --
                -- Den første er forklaringen på, at en elev med én fejlet
                -- bevilling som regel har to: reglen fejler BEGGE de
                -- konfliktende bevillinger, ikke kun den nyeste, så eleven
                -- står uden en brugbar. Indtil det er rettet, er det dét, der
                -- gælder om eleven. Med den gamle
                -- binære test stod en elev med en fejlet og en udløbet
                -- bevilling som Udløbet, og den der skulle handles på var den
                -- eneste, der ikke blev vist.
                --
                -- Samme rækkefølge som $lib/statusRang i frontenden. Ændres
                -- den her, skal den ændres dér: de svarer på det samme for den
                -- samme elev, og listen linker til siden.
                CASE st.status_tekst
                    WHEN N'Fejlet'    THEN 0
                    WHEN N'Aktiv'     THEN 1
                    WHEN N'Kommende'  THEN 2
                    WHEN N'Påbegyndt' THEN 3
                    WHEN N'Ny'        THEN 4
                    WHEN N'Afslag'    THEN 5
                    WHEN N'Ophørt'    THEN 6
                    WHEN N'Udløbet'   THEN 7
                    ELSE 99
                END,
                b.updated_at DESC,
                b.created_at DESC
        ) AS rn
    FROM [Befordringssystemet].[befordring].[Bevilling] b
    LEFT JOIN [Befordringssystemet].[befordring].[Status] st
        ON b.status_id = st.status_id
    -- Filtered BEFORE the ranking, not after: soft-delete never changes the
    -- status, so a bevilling deleted while Aktiv sorts to rn = 1 on the CASE
    -- above and becomes the student's displayed bevilling.
    WHERE b.aktiv = 1
)

SELECT
    e.navne_adresse_beskyttelse,
    e.adresseringsnavn,
    e.cpr,

    b.bevilling_id,
    b.esdh_noegle,
    -- Det opløste link til GO, ved siden af nøglen. Kan ikke udledes af
    -- esdh_noegle — kun rpa-befordring-kontrol kan slå den op — så uden den
    -- her kunne stamdatakortet vise sags-id'et, men ikke linke til sagen,
    -- selv om bevillingskortet lige nedenunder gjorde begge dele.
    b.esdh_url,
    b.status_tekst,

    -- Both the id and the text. The text is what the case page renders; the
    -- id is what anything comparing addresses has to use, since two identical
    -- strings are not a match and Bevilling.adresse_id holds an id. The
    -- conversion RPA compares each legacy bevilling's address against this to
    -- decide whether the student still lives where the bevilling was granted.
    e.adresse_id,
    -- Navngivet som i view_Revurderinger og view_Genbehandling, ikke efter
    -- Adresse-tabellens egen kolonne. De tre views beskriver den samme elev og
    -- læses af den samme Elevoplysninger-komponent; hed feltet forskellige
    -- ting, skulle hvert kaldssted oversætte, og en oversættelse der rammer
    -- forbi giver en tom rubrik frem for en fejl.
    --
    -- Og navnet er mere præcist: det ER folkeregisteradressen, mens
    -- adresse_tekst blot siger "en adresse som tekst".
    ad.adresse_tekst                             AS folkeregister_adresse,

    e.matrikel_id,
    sm.matrikel_navn                             AS skolematrikel,

    e.ungdomsuddannelse_id,
    uu.ungdomsuddannelse_navn,

    COALESCE(sm.matrikel_navn,
             uu.ungdomsuddannelse_navn)          AS skole_navn,

    CASE
        WHEN e.ungdomsuddannelse_id IS NOT NULL THEN 'Ungdomsuddannelse'
        WHEN e.matrikel_id          IS NOT NULL THEN 'Folkeskole'
        ELSE NULL
    END                                          AS skole_type,

    e.skolekode,

    -- Samme grund, og samme navn som de to andre views: gåafstand i km, målt
    -- til skolen. "skoleafstand" siger hverken enhed eller at det er gående.
    e.skoleafstand                               AS gaaafstand_km,
    e.klasseart,
    e.klassebetegnelse,
    e.elevklassetrin,
    e.institution,
    e.bopaelsdistrikt

FROM [Befordringssystemet].[befordring].[Elev] e

LEFT JOIN PrioritizedBevilling b
    ON b.cpr_elev = e.cpr AND b.rn = 1

LEFT JOIN [Befordringssystemet].[befordring].[Adresse] ad
    ON ad.adresse_id = e.adresse_id

LEFT JOIN [Befordringssystemet].[befordring].[Skolematrikel] sm
    ON sm.matrikel_id = e.matrikel_id

LEFT JOIN [Befordringssystemet].[befordring].[Ungdomsuddannelse] uu
    ON uu.ungdomsuddannelse_id = e.ungdomsuddannelse_id;
GO


