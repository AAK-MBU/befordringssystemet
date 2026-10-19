USE [Befordringssystemet]
GO
/****** Object:  Schema [befordring]    Script Date: 14/10/2026 12:53:45 ******/
CREATE SCHEMA [befordring]
GO
/****** Object:  Table [befordring].[Brev]    Script Date: 14/10/2026 12:53:45 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [befordring].[Brev](
	[brev_id] [int] IDENTITY(1,1) NOT NULL,
	[bevilling_id] [int] NOT NULL,
	[cpr_elev] [varchar](10) NOT NULL,
	[reference] [nvarchar](100) NULL,
	[afgoerelsesbrev_tekst] [nvarchar](500) NULL,
	[brev_i_forbindelse_med] [nvarchar](100) NULL,
	[oprettet_tidspunkt] [datetime2](7) NOT NULL,
	[oprettet_af] [nvarchar](200) NULL,
	[afsendt] [bit] NOT NULL,
	[afsendt_tidspunkt] [datetime2](7) NULL,
	[afsendt_af] [nvarchar](200) NULL,
	[aktiv] [bit] NOT NULL,
 CONSTRAINT [PK_Brev] PRIMARY KEY CLUSTERED 
(
	[brev_id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [befordring].[Status]    Script Date: 14/10/2026 12:53:45 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [befordring].[Status](
	[status_id] [int] IDENTITY(1,1) NOT NULL,
	[status_tekst] [varchar](max) NOT NULL,
	[beskrivelse] [varchar](max) NULL,
	[aktiv] [bit] NOT NULL,
 CONSTRAINT [PK_status] PRIMARY KEY CLUSTERED 
(
	[status_id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
/****** Object:  Table [befordring].[Sagsbehandler]    Script Date: 14/10/2026 12:53:45 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [befordring].[Sagsbehandler](
	[sagsbehandler_id] [int] IDENTITY(1,1) NOT NULL,
	[sagsbehandler_tekst] [varchar](max) NOT NULL,
	[beskrivelse] [varchar](max) NULL,
	[aktiv] [bit] NOT NULL,
 CONSTRAINT [PK_sagsbehandler] PRIMARY KEY CLUSTERED 
(
	[sagsbehandler_id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
/****** Object:  Table [befordring].[Elev]    Script Date: 14/10/2026 12:53:45 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [befordring].[Elev](
	[cpr] [varchar](10) NOT NULL,
	[adresseringsnavn] [varchar](max) NULL,
	[navne_adresse_beskyttelse] [bit] NULL,
	[skoleafstand] [float] NULL,
	[klasseart] [varchar](max) NULL,
	[elevklassetrin] [varchar](max) NULL,
	[klassebetegnelse] [varchar](max) NULL,
	[institution] [varchar](max) NULL,
	[bopaelsdistrikt] [varchar](max) NULL,
	[matrikel_id] [int] NULL,
	[ungdomsuddannelse_id] [int] NULL,
	[skolekode] [int] NULL,
	[kraever_genberegning] [bit] NULL,
	[adresse_id] [nvarchar](36) NULL,
 CONSTRAINT [PK_elev] PRIMARY KEY CLUSTERED 
(
	[cpr] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
/****** Object:  Table [befordring].[Bevilling]    Script Date: 14/10/2026 12:53:45 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [befordring].[Bevilling](
	[bevilling_id] [int] IDENTITY(1,1) NOT NULL,
	[cpr_elev] [varchar](10) NOT NULL,
	[status_id] [int] NOT NULL,
	[matrikel_id] [int] NULL,
	[hjemmel_id] [int] NULL,
	[afgoerelsesbrev_id] [int] NULL,
	[revurderingsdato] [date] NULL,
	[befordringsudvalg] [date] NULL,
	[esdh_noegle] [nvarchar](max) NULL,
	[sagsbehandler_id] [int] NULL,
	[ppr_sagsbehandler_id] [int] NULL,
	[ansoegningsdato] [date] NULL,
	[sagsbehandlingsdato] [date] NULL,
	[relation_til_barnet] [varchar](max) NULL,
	[foerste_koersel_dato] [date] NULL,
	[ansoegningstype] [varchar](max) NOT NULL,
	[afstandskriterie_dato] [date] NULL,
	[afstandskriterie_klassetrin] [int] NULL,
	[begrundelse_fra_formular] [varchar](max) NULL,
	[created_at] [datetime2](7) NOT NULL,
	[created_by] [varchar](max) NOT NULL,
	[updated_at] [datetime2](7) NOT NULL,
	[updated_by] [varchar](max) NOT NULL,
	[aktiv] [bit] NOT NULL,
	[ungdomsuddannelse_id] [int] NULL,
	[revurderet_af_ppr] [bit] NULL,
	[statusbemaerkning] [nvarchar](max) NULL,
	[adresse_id] [nvarchar](36) NOT NULL,
	[revurderet_af_br] [bit] NULL,
	[final] [bit] NOT NULL,
	[loebenummer] [int] NULL,
	[genbehandling] [bit] NULL,
	[genbehandling_haandteret] [bit] NULL,
	[genbehandling_bemaerkning] [nvarchar](500) NULL,
	[genbehandling_haandteret_adresse_id] [nvarchar](36) NULL,
	[genbehandling_haandteret_skolekode] [int] NULL,
	[revurdering] [bit] NULL,
	[esdh_url] [nvarchar](500) NULL,
	[os2forms_id] [nvarchar](36) NULL,
	[ansoegningsdata] [nvarchar](max) NULL,
	[gaaafstand_km] [float] NULL,
	[ansvarlig_sagsbehandler_id] [int] NULL,
	[ansvarlig_ppr_sagsbehandler_id] [int] NULL,
 CONSTRAINT [PK_bevilling] PRIMARY KEY CLUSTERED 
(
	[bevilling_id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
/****** Object:  View [befordring].[view_Forsendelse]    Script Date: 14/10/2026 12:53:45 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Letters that have been created but not yet sent — the Forsendelse worklist.
--
-- Creating a letter queues an ATS work item and produces a document; it does
-- not post anything to the parents. This view is the gap between those two.
--
-- Joined here rather than in the caller so the page gets the student's name and
-- the bevilling's løbenummer without a second round trip. The columns from Brev
-- are snapshots taken when the letter was created — see backend/db/migrations/
-- 014_add_brev.sql for why they are not resolved live.

CREATE   VIEW [befordring].[view_Forsendelse]
AS
SELECT
    br.brev_id,
    br.reference,

    br.bevilling_id,
    b.loebenummer,
    b.esdh_noegle,
    -- The deep link into GO. Resolved by rpa-befordring-kontrol and the
    -- nightly run; NULL until one of them has. Exposed so Forsendelse can
    -- link the sags-id instead of printing it for someone to search by hand.
    b.esdh_url,

    br.cpr_elev,
    e.adresseringsnavn,

    br.afgoerelsesbrev_tekst,
    br.brev_i_forbindelse_med,

    br.oprettet_tidspunkt,
    br.oprettet_af,

    -- Whole days the letter has been waiting. Lets the page highlight a
    -- backlog without every client recomputing it from a timestamp.
    DATEDIFF(DAY, br.oprettet_tidspunkt, GETDATE()) AS dage_ventet,

    st.status_tekst     AS bevilling_status,
    sb.sagsbehandler_tekst AS sagsbehandler

FROM      [befordring].[Brev]           br
LEFT JOIN [befordring].[Bevilling]      b   ON b.bevilling_id    = br.bevilling_id
LEFT JOIN [befordring].[Elev]           e   ON e.cpr             = br.cpr_elev
LEFT JOIN [befordring].[Status]         st  ON st.status_id      = b.status_id
LEFT JOIN [befordring].[Sagsbehandler]  sb  ON sb.sagsbehandler_id = b.sagsbehandler_id

-- The worklist is exactly "created, not sent". A soft-deleted letter, or one
-- on a soft-deleted bevilling, is not work anybody should be doing.
WHERE
    br.afsendt = 0
AND br.aktiv   = 1
AND ISNULL(b.aktiv, 0) = 1;
GO
/****** Object:  Table [befordring].[PPR_Sagsbehandler]    Script Date: 14/10/2026 12:53:45 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [befordring].[PPR_Sagsbehandler](
	[ppr_sagsbehandler_id] [int] IDENTITY(1,1) NOT NULL,
	[ppr_sagsbehandler_tekst] [varchar](max) NOT NULL,
	[beskrivelse] [varchar](max) NULL,
	[aktiv] [bit] NOT NULL,
 CONSTRAINT [PK_ppr_sagsbehandler] PRIMARY KEY CLUSTERED 
(
	[ppr_sagsbehandler_id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
/****** Object:  Table [befordring].[Skolematrikel]    Script Date: 14/10/2026 12:53:45 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [befordring].[Skolematrikel](
	[matrikel_id] [int] IDENTITY(1,1) NOT NULL,
	[matrikel_navn] [varchar](max) NOT NULL,
	[matrikel_adresse] [varchar](max) NOT NULL,
	[skolekode] [int] NOT NULL,
	[er_matrikel_hovedadresse] [bit] NOT NULL,
	[latitude] [float] NULL,
	[longitude] [float] NULL,
 CONSTRAINT [PK_skolematrikel] PRIMARY KEY CLUSTERED 
(
	[matrikel_id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
/****** Object:  Table [befordring].[Hjemmel]    Script Date: 14/10/2026 12:53:45 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [befordring].[Hjemmel](
	[hjemmel_id] [int] IDENTITY(1,1) NOT NULL,
	[hjemmel_tekst] [varchar](max) NOT NULL,
	[beskrivelse] [varchar](max) NULL,
	[aktiv] [bit] NOT NULL,
 CONSTRAINT [PK_hjemmel] PRIMARY KEY CLUSTERED 
(
	[hjemmel_id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
/****** Object:  Table [befordring].[Afgoerelsesbrev]    Script Date: 14/10/2026 12:53:45 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [befordring].[Afgoerelsesbrev](
	[afgoerelsesbrev_id] [int] IDENTITY(1,1) NOT NULL,
	[afgoerelsesbrev_tekst] [varchar](max) NOT NULL,
	[beskrivelse] [varchar](max) NULL,
	[aktiv] [bit] NOT NULL,
 CONSTRAINT [PK_afgoerelsesbrev] PRIMARY KEY CLUSTERED 
(
	[afgoerelsesbrev_id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
/****** Object:  Table [befordring].[Adresse]    Script Date: 14/10/2026 12:53:45 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [befordring].[Adresse](
	[adresse_id] [nvarchar](36) NOT NULL,
	[adresse_tekst] [nvarchar](500) NULL,
	[latitude] [float] NULL,
	[longitude] [float] NULL,
 CONSTRAINT [PK_Adresse] PRIMARY KEY CLUSTERED 
(
	[adresse_id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  View [befordring].[view_Genbehandling]    Script Date: 14/10/2026 12:53:45 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


/* ---------- view_Genbehandling: bevillinger flagged for genbehandling ----------
   Triggered by data mismatches (skolekode or adresse) between the bevilling
   and the student's current CPR data. Separate from the date-driven Revurdering
   page. Sign-off is a single flag (genbehandling_haandteret) rather than the
   two-step PPR/BR flow used for revurdering.
*/
CREATE   VIEW [befordring].[view_Genbehandling] AS
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
    sm.matrikel_navn                AS skole_navn,
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
    s.status_tekst,
    b.statusbemaerkning
FROM       [befordring].[Bevilling]          b
INNER JOIN [befordring].[Status]             s   ON s.status_id              = b.status_id
INNER JOIN [befordring].[Elev]               e   ON e.cpr                    = b.cpr_elev
INNER JOIN [befordring].[Adresse]            a   ON a.adresse_id             = e.adresse_id
LEFT  JOIN [befordring].[Adresse]            ba  ON ba.adresse_id            = b.adresse_id
LEFT  JOIN [befordring].[Skolematrikel]      sm  ON sm.matrikel_id           = b.matrikel_id
LEFT  JOIN [befordring].[Hjemmel]            h   ON h.hjemmel_id             = b.hjemmel_id
LEFT  JOIN [befordring].[Afgoerelsesbrev]    ab  ON ab.afgoerelsesbrev_id    = b.afgoerelsesbrev_id
LEFT  JOIN [befordring].[PPR_Sagsbehandler]  ppr ON ppr.ppr_sagsbehandler_id = b.ppr_sagsbehandler_id
LEFT  JOIN [befordring].[Sagsbehandler]      sb  ON sb.sagsbehandler_id      = b.sagsbehandler_id
WHERE      b.aktiv = 1
AND        b.genbehandling = 1;
GO
/****** Object:  Table [befordring].[Part]    Script Date: 14/10/2026 12:53:45 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [befordring].[Part](
	[part_id] [int] IDENTITY(1,1) NOT NULL,
	[cpr_elev] [varchar](10) NOT NULL,
	[fulde_navn] [nvarchar](200) NULL,
	[cpr_nummer] [varchar](10) NULL,
	[relation] [nvarchar](50) NULL,
	[telefonnummer] [varchar](20) NULL,
	[oprettet_tidspunkt] [datetime2](7) NOT NULL,
	[oprettet_af] [nvarchar](100) NULL,
	[aktiv] [bit] NOT NULL,
	[adresse_id] [nvarchar](36) NULL,
 CONSTRAINT [PK_Part] PRIMARY KEY CLUSTERED 
(
	[part_id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [befordring].[Befordringstype]    Script Date: 14/10/2026 12:53:45 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [befordring].[Befordringstype](
	[befordringstype_id] [int] IDENTITY(1,1) NOT NULL,
	[befordringstype_tekst] [varchar](max) NOT NULL,
	[beskrivelse] [varchar](max) NULL,
	[aktiv] [bit] NOT NULL,
 CONSTRAINT [PK_befordringstype] PRIMARY KEY CLUSTERED 
(
	[befordringstype_id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
/****** Object:  Table [befordring].[Koersel]    Script Date: 14/10/2026 12:53:45 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [befordring].[Koersel](
	[koersel_id] [int] IDENTITY(1,1) NOT NULL,
	[bevilling_id] [int] NOT NULL,
	[gyldig_fra] [date] NOT NULL,
	[gyldig_til] [date] NOT NULL,
	[tidspunkt_id] [int] NULL,
	[befordringstype_id] [int] NOT NULL,
	[bevilget_koereafstand_pr_vej] [float] NULL,
	[taxa_id] [varchar](max) NULL,
	[kommentar] [varchar](max) NULL,
	[final] [bit] NOT NULL,
	[aktiv] [bit] NOT NULL,
	[rutetype_id] [int] NULL,
	[koersel_til_institution] [bit] NULL,
	[max_minutter_i_transport] [int] NULL,
	[koerselsgodtgoerelse_modtager_id] [int] NULL,
	[koerselsgodtgoerelse_modtager_cpr] [nvarchar](10) NULL,
	[transporttid_i_bus] [int] NULL,
	[skift_med_bus] [int] NULL,
 CONSTRAINT [PK_koersel] PRIMARY KEY CLUSTERED 
(
	[koersel_id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
/****** Object:  Table [befordring].[Foraelder]    Script Date: 14/10/2026 12:53:45 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [befordring].[Foraelder](
	[cpr_foraelder] [varchar](10) NOT NULL,
	[cpr_elev] [varchar](10) NOT NULL,
	[adresseringsnavn] [varchar](max) NULL,
	[navne_adresse_beskyttelse] [bit] NULL,
	[maa_vide_barns_adresse] [bit] NULL,
	[adresse_id] [nvarchar](36) NULL,
	[relation] [varchar](50) NULL,
 CONSTRAINT [PK_Foraelder_cpr_foraelder_cpr_elev] PRIMARY KEY CLUSTERED 
(
	[cpr_foraelder] ASC,
	[cpr_elev] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
/****** Object:  View [befordring].[view_Koerselsgodtgoerelse_Modtagere]    Script Date: 14/10/2026 12:53:45 ******/
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

CREATE   VIEW [befordring].[view_Koerselsgodtgoerelse_Modtagere]
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
/****** Object:  View [befordring].[view_Revurderinger]    Script Date: 14/10/2026 12:53:45 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


/* ---------- view_Revurderinger: filter on the flag ---------- */
CREATE   VIEW [befordring].[view_Revurderinger] AS
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
    sm.matrikel_navn                AS skole_navn,
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
    s.status_tekst,
    b.statusbemaerkning
FROM       [befordring].[Bevilling]          b
INNER JOIN [befordring].[Status]             s   ON s.status_id              = b.status_id
INNER JOIN [befordring].[Elev]               e   ON e.cpr                    = b.cpr_elev
INNER JOIN [befordring].[Adresse]            a   ON a.adresse_id             = e.adresse_id
LEFT  JOIN [befordring].[Adresse]            ba  ON ba.adresse_id            = b.adresse_id
LEFT  JOIN [befordring].[Skolematrikel]      sm  ON sm.matrikel_id           = b.matrikel_id
LEFT  JOIN [befordring].[Hjemmel]            h   ON h.hjemmel_id             = b.hjemmel_id
LEFT  JOIN [befordring].[Afgoerelsesbrev]    ab  ON ab.afgoerelsesbrev_id    = b.afgoerelsesbrev_id
LEFT  JOIN [befordring].[PPR_Sagsbehandler]  ppr ON ppr.ppr_sagsbehandler_id = b.ppr_sagsbehandler_id
LEFT  JOIN [befordring].[Sagsbehandler]      sb  ON sb.sagsbehandler_id      = b.sagsbehandler_id
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
/****** Object:  View [befordring].[view_All_Active_Bevillinger]    Script Date: 14/10/2026 12:53:45 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO




CREATE   VIEW [befordring].[view_All_Active_Bevillinger]
AS

SELECT
    e.adresseringsnavn,
    b.cpr_elev,
    s.status_tekst,
    b.esdh_noegle,
    sb.sagsbehandler_tekst AS sagsbehandler,
    ppr.ppr_sagsbehandler_tekst
FROM
    [Befordringssystemet].[befordring].[Bevilling] b

LEFT JOIN
    [Befordringssystemet].[befordring].Elev e 
    ON b.cpr_elev = e.cpr

LEFT JOIN
    [Befordringssystemet].[befordring].Sagsbehandler sb 
    ON b.sagsbehandler_id = sb.sagsbehandler_id

LEFT JOIN
    [Befordringssystemet].[befordring].Status s 
    ON b.status_id = s.status_id

LEFT JOIN
    [Befordringssystemet].[befordring].PPR_Sagsbehandler ppr 
    ON b.ppr_sagsbehandler_id = ppr.ppr_sagsbehandler_id

WHERE
    /* Both halves are needed: status_tekst alone lets through a soft-deleted
       bevilling that was Aktiv when it was deleted. */
    b.aktiv = 1
    AND s.status_tekst = 'Aktiv';
GO
/****** Object:  View [befordring].[view_New_Applications]    Script Date: 14/10/2026 12:53:45 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE   VIEW [befordring].[view_New_Applications]
AS
SELECT
    b.bevilling_id,
    e.adresseringsnavn,
    b.cpr_elev,
    b.esdh_noegle,
    b.esdh_url,
    b.ansoegningsdato,
    b.ansoegningstype,
    b.foerste_koersel_dato,
    -- Carries BOTH halves of the kørselstype question: the types the citizen
    -- ticked, and — once a caseworker has made the call — the one the case is
    -- being treated as asking for. Nye ansøgninger shows the second where it
    -- exists and falls back to the first where it does not, which is why the
    -- whole document is handed over rather than a derived label.
    b.ansoegningsdata,
    b.sagsbehandler_id,
    sb.sagsbehandler_tekst AS sagsbehandler,
    b.ppr_sagsbehandler_id,
    ppr.ppr_sagsbehandler_tekst,
    s.status_tekst
FROM
    [Befordringssystemet].[befordring].[Bevilling] b
LEFT JOIN
    [Befordringssystemet].[befordring].Elev e
    ON b.cpr_elev = e.cpr
LEFT JOIN
    [Befordringssystemet].[befordring].Sagsbehandler sb
    ON b.sagsbehandler_id = sb.sagsbehandler_id
LEFT JOIN
    [Befordringssystemet].[befordring].Status s
    ON b.status_id = s.status_id
LEFT JOIN
    [Befordringssystemet].[befordring].PPR_Sagsbehandler ppr
    ON b.ppr_sagsbehandler_id = ppr.ppr_sagsbehandler_id
WHERE
    -- Soft-deleted bevillinger keep whatever status they had, so a deleted
    -- one still sitting at Ny/Påbegyndt would show on Nye ansøgninger.
    -- Note the parentheses: AND binds tighter than OR, so without them the
    -- aktiv filter would apply to the first status only.
    b.aktiv = 1
    AND (s.status_tekst = 'Ny' OR s.status_tekst = 'Påbegyndt');
GO
/****** Object:  Table [befordring].[Ungdomsuddannelse]    Script Date: 14/10/2026 12:53:45 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [befordring].[Ungdomsuddannelse](
	[ungdomsuddannelse_id] [int] IDENTITY(1,1) NOT NULL,
	[ungdomsuddannelse_navn] [nvarchar](max) NOT NULL,
	[ungdomsuddannelse_adresse] [varchar](max) NOT NULL,
	[latitude] [float] NULL,
	[longitude] [float] NULL,
 CONSTRAINT [PK_Ungdomsuddannelse] PRIMARY KEY CLUSTERED 
(
	[ungdomsuddannelse_id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
/****** Object:  View [befordring].[view_Stamdata]    Script Date: 14/10/2026 12:53:45 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE   VIEW [befordring].[view_Stamdata]
AS

WITH PrioritizedBevilling AS (
    SELECT
        b.*,
        st.status_tekst,
        ROW_NUMBER() OVER (
            PARTITION BY b.cpr_elev
            ORDER BY
                CASE WHEN st.status_tekst = 'Aktiv' THEN 0 ELSE 1 END,
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
/****** Object:  Table [befordring].[Hjaelpemiddel]    Script Date: 14/10/2026 12:53:45 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [befordring].[Hjaelpemiddel](
	[hjaelpemiddel_id] [int] IDENTITY(1,1) NOT NULL,
	[hjaelpemiddel_tekst] [varchar](max) NOT NULL,
	[beskrivelse] [varchar](max) NULL,
	[aktiv] [bit] NOT NULL,
 CONSTRAINT [PK_hjaelpemiddel] PRIMARY KEY CLUSTERED 
(
	[hjaelpemiddel_id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
/****** Object:  Table [befordring].[Bevilling_Hjaelpemiddel_LINK]    Script Date: 14/10/2026 12:53:45 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [befordring].[Bevilling_Hjaelpemiddel_LINK](
	[bevilling_id] [int] NOT NULL,
	[hjaelpemiddel_id] [int] NOT NULL,
 CONSTRAINT [PK_Bevilling_Hjaelpemiddel] PRIMARY KEY CLUSTERED 
(
	[bevilling_id] ASC,
	[hjaelpemiddel_id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  View [befordring].[view_Student_Bevillinger]    Script Date: 14/10/2026 12:53:45 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO






CREATE   VIEW [befordring].[view_Student_Bevillinger]
AS
SELECT
    b.bevilling_id,
    -- Per-child display number. bevilling_id stays the real key; this is what
    -- the UI labels a bevilling with. See migration 008.
    b.loebenummer,
    b.created_at,
    b.updated_at,

    e.navne_adresse_beskyttelse,
    e.adresseringsnavn,
    e.cpr,

    b.status_id,
    st.status_tekst,
    b.statusbemaerkning,
    b.revurdering,
    -- Genbehandling: the bevilling's school or address no longer matches the
    -- elev's current CPR data. Exposed so the bevilling card can show it —
    -- previously it was only visible on the Genbehandling page.
    b.genbehandling,
    b.genbehandling_bemaerkning,
    b.final,
    -- Hvad borgeren ansøgte om, som JSON. Forudfylder "+ Ny kørselsrække",
    -- så sagsbehandleren ikke skriver det ind igen. Se migration 029.
    b.ansoegningsdata,
    b.esdh_noegle,
    b.esdh_url,
    e.elevklassetrin,

    b.sagsbehandlingsdato,
    ba.adresse_tekst                                              AS adresse_for_bevilling,
    b.adresse_id,
    ba.latitude                                                   AS adresse_latitude,
    ba.longitude                                                  AS adresse_longitude,
    b.ansoegningstype,
    b.ansoegningsdato,
    -- The date the bevilling's kørsel starts. Exposed so the PPR conversion
    -- bot can tell its own bevillinger apart: every bevilling it creates for
    -- one case carries the same esdh_noegle (the PPR case id), so that alone
    -- cannot answer "has this one been created already?" on a re-run.
    b.foerste_koersel_dato,

    b.matrikel_id,
    sk.matrikel_navn,

    b.ungdomsuddannelse_id,
    uu.ungdomsuddannelse_navn,

    COALESCE(sk.matrikel_navn, uu.ungdomsuddannelse_navn)         AS skole_navn,

    e.skoleafstand,

    -- Gåafstand mellem BEVILLINGENS adresse og BEVILLINGENS skole.
    --
    -- e.skoleafstand ovenfor måler elevens nuværende folkeregisteradresse mod
    -- den skole elevens nuværende data peger på. Det er et andet par, hver
    -- gang en ansøgning følger en flytning eller en henvisning — og netop der
    -- har sagsbehandleren brug for tallet. Begge vises, så man kan se den
    -- nuværende situation ved siden af den, ansøgningen handler om.
    --
    -- NULL betyder "ikke beregnet", aldrig nul: intet er bagudfyldt, og
    -- værdien skrives først ved oprettelse, ved skift af adresse eller skole,
    -- og når sagsbehandleren trykker genberegn. Se migration 030.
    b.gaaafstand_km                                              AS bevilling_gaaafstand_km,

    STRING_AGG(CAST(h.hjaelpemiddel_id AS varchar(20)), ',')     AS hjaelpemiddel_ids,
    STRING_AGG(h.hjaelpemiddel_tekst, ', ')                      AS hjaelpemidler,

    b.afstandskriterie_dato,
    b.afstandskriterie_klassetrin,
    b.relation_til_barnet,
    b.revurderingsdato,
    b.befordringsudvalg,

    b.hjemmel_id,
    hjemmel.hjemmel_tekst,

    b.afgoerelsesbrev_id,
    afg.afgoerelsesbrev_tekst,

    b.sagsbehandler_id,
    sb.sagsbehandler_tekst,

    b.ppr_sagsbehandler_id,
    ppr.ppr_sagsbehandler_tekst
FROM
    [Befordringssystemet].[befordring].[Bevilling]                b
LEFT JOIN [Befordringssystemet].[befordring].[Elev]                     e       ON e.cpr                    = b.cpr_elev
LEFT JOIN [Befordringssystemet].[befordring].[Adresse]                  ba      ON ba.adresse_id             = b.adresse_id
LEFT JOIN [Befordringssystemet].[befordring].[Status]                   st      ON b.status_id               = st.status_id
LEFT JOIN [Befordringssystemet].[befordring].[Skolematrikel]            sk      ON sk.matrikel_id            = b.matrikel_id
LEFT JOIN [Befordringssystemet].[befordring].[Ungdomsuddannelse]        uu      ON uu.ungdomsuddannelse_id   = b.ungdomsuddannelse_id
LEFT JOIN [Befordringssystemet].[befordring].[Bevilling_Hjaelpemiddel_LINK] bhl ON b.bevilling_id            = bhl.bevilling_id
LEFT JOIN [Befordringssystemet].[befordring].[Hjaelpemiddel]            h       ON h.hjaelpemiddel_id        = bhl.hjaelpemiddel_id
LEFT JOIN [Befordringssystemet].[befordring].[Hjemmel]                  hjemmel ON b.hjemmel_id              = hjemmel.hjemmel_id
LEFT JOIN [Befordringssystemet].[befordring].[Afgoerelsesbrev]          afg     ON b.afgoerelsesbrev_id      = afg.afgoerelsesbrev_id
LEFT JOIN [Befordringssystemet].[befordring].[Sagsbehandler]            sb      ON b.sagsbehandler_id        = sb.sagsbehandler_id
LEFT JOIN [Befordringssystemet].[befordring].[PPR_Sagsbehandler]        ppr     ON b.ppr_sagsbehandler_id    = ppr.ppr_sagsbehandler_id

WHERE
    b.aktiv = 1

GROUP BY
    b.bevilling_id, b.loebenummer, b.created_at, b.updated_at,
    e.navne_adresse_beskyttelse, e.adresseringsnavn, e.cpr,
    b.status_id, st.status_tekst, b.statusbemaerkning, b.revurdering,
    b.genbehandling, b.genbehandling_bemaerkning, b.final, b.ansoegningsdata,
    b.esdh_noegle, b.esdh_url, e.elevklassetrin,
    b.sagsbehandlingsdato,
    ba.adresse_tekst,
    b.adresse_id,
    ba.latitude,
    ba.longitude,
    b.ansoegningstype,
    b.ansoegningsdato,
    -- The date the bevilling's kørsel starts. Exposed so the PPR conversion
    -- bot can tell its own bevillinger apart: every bevilling it creates for
    -- one case carries the same esdh_noegle (the PPR case id), so that alone
    -- cannot answer "has this one been created already?" on a re-run.
    b.foerste_koersel_dato,
    b.matrikel_id, sk.matrikel_navn,
    b.ungdomsuddannelse_id, uu.ungdomsuddannelse_navn,
    e.skoleafstand, b.gaaafstand_km,
    b.afstandskriterie_dato, b.afstandskriterie_klassetrin,
    b.relation_til_barnet, b.revurderingsdato, b.befordringsudvalg,
    b.hjemmel_id, hjemmel.hjemmel_tekst,
    b.afgoerelsesbrev_id, afg.afgoerelsesbrev_tekst,
    b.sagsbehandler_id, sb.sagsbehandler_tekst,
    b.ppr_sagsbehandler_id, ppr.ppr_sagsbehandler_tekst;
GO
/****** Object:  Table [befordring].[Rutetype]    Script Date: 14/10/2026 12:53:45 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [befordring].[Rutetype](
	[rutetype_id] [int] IDENTITY(1,1) NOT NULL,
	[rutetype_tekst] [nvarchar](255) NOT NULL,
	[beskrivelse] [nvarchar](1000) NULL,
	[aktiv] [bit] NOT NULL,
	[sorteringsorden] [int] NULL,
 CONSTRAINT [PK_Rutetype] PRIMARY KEY CLUSTERED 
(
	[rutetype_id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [befordring].[KoerselstypeTillaeg]    Script Date: 14/10/2026 12:53:45 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [befordring].[KoerselstypeTillaeg](
	[tillaeg_id] [int] IDENTITY(1,1) NOT NULL,
	[tillaeg_tekst] [varchar](max) NOT NULL,
	[beskrivelse] [varchar](max) NULL,
	[aktiv] [bit] NOT NULL,
 CONSTRAINT [PK_koerselstype_tillaeg] PRIMARY KEY CLUSTERED 
(
	[tillaeg_id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
/****** Object:  Table [befordring].[Koersel_KoerselstypeTillaeg_LINK]    Script Date: 14/10/2026 12:53:45 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [befordring].[Koersel_KoerselstypeTillaeg_LINK](
	[koersel_id] [int] NOT NULL,
	[tillaeg_id] [int] NOT NULL,
 CONSTRAINT [PK_Koersel_KoerselstypeTillaeg] PRIMARY KEY CLUSTERED 
(
	[koersel_id] ASC,
	[tillaeg_id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [befordring].[Ugedag]    Script Date: 14/10/2026 12:53:45 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [befordring].[Ugedag](
	[dag_id] [int] IDENTITY(1,1) NOT NULL,
	[dag_tekst] [varchar](max) NOT NULL,
	[beskrivelse] [varchar](max) NULL,
	[aktiv] [bit] NOT NULL,
 CONSTRAINT [PK_ugedag] PRIMARY KEY CLUSTERED 
(
	[dag_id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
/****** Object:  Table [befordring].[Koersel_Ugedag_LINK]    Script Date: 14/10/2026 12:53:45 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [befordring].[Koersel_Ugedag_LINK](
	[koersel_id] [int] NOT NULL,
	[dag_id] [int] NOT NULL,
 CONSTRAINT [PK_Koersel_Ugedag] PRIMARY KEY CLUSTERED 
(
	[koersel_id] ASC,
	[dag_id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [befordring].[Tidspunkt]    Script Date: 14/10/2026 12:53:45 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [befordring].[Tidspunkt](
	[tidspunkt_id] [int] IDENTITY(1,1) NOT NULL,
	[tidspunkt_tekst] [varchar](max) NOT NULL,
	[beskrivelse] [varchar](max) NULL,
	[aktiv] [bit] NOT NULL,
 CONSTRAINT [PK_tidspunkt] PRIMARY KEY CLUSTERED 
(
	[tidspunkt_id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
/****** Object:  View [befordring].[view_Bevilling_Koerselsraekker]    Script Date: 14/10/2026 12:53:45 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


CREATE   VIEW [befordring].[view_Bevilling_Koerselsraekker]
AS
    SELECT
        k.koersel_id,
        b.bevilling_id,

        k.tidspunkt_id,
        t.tidspunkt_tekst,

        k.befordringstype_id,
        bt.befordringstype_tekst,

        k.rutetype_id,
        rt.rutetype_tekst,
        -- Befordrings rækkefølge for rutetyper, brugt som TIE-BREAK under
        -- datosorteringen: den afgør kun rækkefølgen mellem rækker med samme
        -- gyldig_fra og gyldig_til. En kolonne frem for en liste i koden,
        -- fordi rækkefølgen hverken kan udledes af navnet eller af id'et —
        -- og fordi både UI'et og brevet skal sortere ens. Se migration 032.
        -- NULL på de udgående typer, så de sorterer sidst.
        rt.sorteringsorden          AS rutetype_sortering,

        kt.tillaeg_ids,
        kt.tillaeg_tekst,

        k.bevilget_koereafstand_pr_vej,

        ud.dag_ids,
        ud.dage,

        k.gyldig_fra,
        k.gyldig_til,
        k.taxa_id,
        k.kommentar,

        k.transporttid_i_bus,
        k.skift_med_bus,

        k.koersel_til_institution,
        k.max_minutter_i_transport,
        k.koerselsgodtgoerelse_modtager_id,
        k.koerselsgodtgoerelse_modtager_cpr,

        k.final
    FROM
        [Befordringssystemet].[befordring].[Koersel] k
    LEFT JOIN
        [Befordringssystemet].[befordring].[Bevilling] b
        ON k.bevilling_id = b.bevilling_id
    LEFT JOIN
        [Befordringssystemet].[befordring].[Tidspunkt] t
        ON k.tidspunkt_id = t.tidspunkt_id
    LEFT JOIN
        [Befordringssystemet].[befordring].[Befordringstype] bt
        ON k.befordringstype_id = bt.befordringstype_id
    LEFT JOIN
        [Befordringssystemet].[befordring].[Rutetype] rt
        ON k.rutetype_id = rt.rutetype_id
    LEFT JOIN (
        SELECT
            ktt_link.koersel_id,
            STRING_AGG(CAST(ktt_link.tillaeg_id AS varchar(20)), ',') AS tillaeg_ids,
            STRING_AGG(ktt.tillaeg_tekst, ', ') AS tillaeg_tekst
        FROM
            [Befordringssystemet].[befordring].[Koersel_KoerselstypeTillaeg_LINK] ktt_link
        INNER JOIN
            [Befordringssystemet].[befordring].[KoerselstypeTillaeg] ktt
            ON ktt.tillaeg_id = ktt_link.tillaeg_id
        GROUP BY
            ktt_link.koersel_id
    ) kt
        ON k.koersel_id = kt.koersel_id
    LEFT JOIN (
        SELECT
            ku_link.koersel_id,
            STRING_AGG(CAST(ku_link.dag_id AS varchar(20)), ',') AS dag_ids,
            STRING_AGG(u.dag_tekst, ', ') AS dage
        FROM
            [Befordringssystemet].[befordring].[Koersel_Ugedag_LINK] ku_link
        INNER JOIN
            [Befordringssystemet].[befordring].[Ugedag] u
            ON u.dag_id = ku_link.dag_id
        GROUP BY
            ku_link.koersel_id
    ) ud
        ON k.koersel_id = ud.koersel_id
    -- Soft-deleted kørselsrækker must not come back through this view.
    -- The callers that read it — get_student_bevillinger, get_revurderinger,
    -- get_genbehandlinger — each repeat AND k.aktiv = 1 on their own join.
    -- Redundant against this view, kept because a reader of those queries
    -- should not have to open this file to know deleted rows are excluded.
    WHERE k.aktiv = 1;

GO
/****** Object:  View [befordring].[view_ParentData]    Script Date: 14/10/2026 12:53:45 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


CREATE   VIEW [befordring].[view_ParentData]
AS
SELECT
    f.cpr_elev,
    f.adresseringsnavn,
    f.cpr_foraelder,
    ad.adresse_tekst,
    f.navne_adresse_beskyttelse,
    f.maa_vide_barns_adresse,
    f.relation,

    CASE
        WHEN f.relation = 'Mor' THEN 1
        WHEN f.relation = 'Far' THEN 2
        ELSE 99
    END AS foraelderrolle_sortering

FROM
    [Befordringssystemet].[befordring].[Foraelder] f

LEFT JOIN
    [Befordringssystemet].[befordring].[Adresse] ad
    ON ad.adresse_id = f.adresse_id;
GO
/****** Object:  View [befordring].[view_All_Bevillinger]    Script Date: 14/10/2026 12:53:45 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO




/* ---------- view_All_Bevillinger: expose the flag ---------- */
CREATE   VIEW [befordring].[view_All_Bevillinger]
AS
SELECT
    b.bevilling_id,
    e.adresseringsnavn,
    b.cpr_elev,
    s.status_tekst,
    b.statusbemaerkning,
    b.revurdering,
	b.final,
    b.esdh_noegle,
    b.esdh_url,
    sb.sagsbehandler_tekst      AS sagsbehandler,
    ppr.ppr_sagsbehandler_tekst,
    COALESCE(sk.matrikel_navn, uu.ungdomsuddannelse_navn) AS skole_navn
FROM      [Befordringssystemet].[befordring].[Bevilling]         b
LEFT JOIN [Befordringssystemet].[befordring].[Elev]              e   ON e.cpr                    = b.cpr_elev
LEFT JOIN [Befordringssystemet].[befordring].[Sagsbehandler]     sb  ON sb.sagsbehandler_id      = b.sagsbehandler_id
LEFT JOIN [Befordringssystemet].[befordring].[Status]            s   ON s.status_id              = b.status_id
LEFT JOIN [Befordringssystemet].[befordring].[PPR_Sagsbehandler] ppr ON ppr.ppr_sagsbehandler_id = b.ppr_sagsbehandler_id
LEFT JOIN [Befordringssystemet].[befordring].[Skolematrikel]     sk  ON sk.matrikel_id           = b.matrikel_id
LEFT JOIN [Befordringssystemet].[befordring].[Ungdomsuddannelse] uu  ON uu.ungdomsuddannelse_id  = b.ungdomsuddannelse_id
/* Soft-deleted bevillinger keep whatever status they had when they were
   deleted, so without this a deleted bevilling still reading 'Aktiv' shows up
   on the overview — and wins the per-student row selection in
   overview_service.get_alle_bevillinger, which prefers an active one.
   view_Student_Bevillinger has always filtered this; these two had not. */
WHERE
    b.aktiv = 1;
GO
/****** Object:  View [befordring].[view_Letter_BevillingData]    Script Date: 14/10/2026 12:53:45 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE   VIEW [befordring].[view_Letter_BevillingData]
AS
SELECT
    b.bevilling_id,
    e.cpr                           AS barnets_cpr,
    e.adresseringsnavn              AS barnets_fulde_navn,
    -- Barnets adresse, som brevet skriver den. Bevillingens adresse vinder
    -- over folkeregisterets: en flytning meldes til os før den slår igennem i
    -- folkeregisteret, og sagsbehandleren skriver så den nye adresse direkte
    -- på bevillingen. Uden COALESCE her blev brevet sendt med den gamle.
    --
    -- Navnet er bevaret fordi skabelonerne i api-skabelonmotor slår op på
    -- {folkeregisteradresse}; at omdøbe det her ville tømme feltet i hvert
    -- eneste brev. Den rigtige oprydning er at omdøbe pladsholderen dér og
    -- her samtidig — se adresse_for_bevilling nedenfor, som er den samme
    -- værdi under et ærligt navn.
    --
    -- Fallback, ikke erstatning: adresse_id er nullable på Bevilling, og en
    -- bevilling uden adresse skal give folkeregisteradressen frem for et
    -- tomt felt i et afgørelsesbrev.
    COALESCE(bad.adresse_tekst, ad.adresse_tekst) AS folkeregisteradresse,
    e.institution,
    e.klasseart,
    e.klassebetegnelse,
    e.elevklassetrin                AS personligt_klassetrin,
    e.bopaelsdistrikt,
    -- Samme værdi som folkeregisteradresse ovenfor, bortset fra fallbacket:
    -- her er NULL stadig NULL, så det er muligt at se, om bevillingen
    -- faktisk bærer en adresse.
    bad.adresse_tekst               AS adresse_for_bevilling,
    b.esdh_noegle                   AS sags_nummer,
    st.status_tekst                 AS status,
    -- School can be a folkeskole (Skolematrikel) OR an ungdomsuddannelse.
    -- Fall back to the ungdomsuddannelse so {skole}/{skolematrikel} resolve
    -- for both student types.
    COALESCE(sk.matrikel_navn,    uu.ungdomsuddannelse_navn)    AS skole,
    COALESCE(sk.matrikel_adresse, uu.ungdomsuddannelse_adresse) AS skolematrikel,
    -- Gåafstanden for DENNE bevilling: dens egen adresse mod dens egen skole.
    --
    -- Tidligere e.skoleafstand, som måler elevens nuværende
    -- folkeregisteradresse mod den skole elevens nuværende data peger på.
    -- Breve skrives ofte på KOMMENDE bevillinger, hvor netop adressen eller
    -- skolen er en anden — så brevet kom til at oplyse en afstand, der hørte
    -- til en anden situation end den, brevet handler om.
    --
    -- NULL betyder "ikke beregnet". Der falles bevidst IKKE tilbage på
    -- e.skoleafstand: et forkert tal i et afgørelsesbrev er værre end et
    -- tomt felt. Brevoprettelsen måler selv, hvis værdien mangler — se
    -- BevillingService.genberegn_gaaafstand(only_if_missing=True).
    b.gaaafstand_km                 AS gaaafstand_km,
    hjemmel.hjemmel_tekst           AS hjemmel,
    afg.afgoerelsesbrev_tekst       AS afgoerelsesbrev,
    sb.sagsbehandler_tekst          AS sagsbehandler,
    ppr.ppr_sagsbehandler_tekst     AS ppr_ansvarlig,
    CONVERT(varchar(10), b.ansoegningsdato,       105) AS modtagelsesdato,
    CONVERT(varchar(10), b.sagsbehandlingsdato,   105) AS sagsbehandlingsdato,
    CONVERT(varchar(10), b.revurderingsdato,      105) AS revurdering,
    CONVERT(varchar(10), b.befordringsudvalg,     105) AS befordringsudvalg,
    CONVERT(varchar(10), b.afstandskriterie_dato, 105) AS afstandskriterie_dato,
    b.afstandskriterie_klassetrin,
    b.relation_til_barnet           AS ansoeger_relation,
    hjaelpemidler.hjaelpemidler
FROM
    [Befordringssystemet].[befordring].[Bevilling]              b
LEFT JOIN [Befordringssystemet].[befordring].[Elev]                   e       ON e.cpr                    = b.cpr_elev
LEFT JOIN [Befordringssystemet].[befordring].[Adresse]                ad      ON ad.adresse_id             = e.adresse_id
LEFT JOIN [Befordringssystemet].[befordring].[Adresse]                bad     ON bad.adresse_id            = b.adresse_id
LEFT JOIN [Befordringssystemet].[befordring].[Status]                 st      ON st.status_id              = b.status_id
LEFT JOIN [Befordringssystemet].[befordring].[Skolematrikel]          sk      ON sk.matrikel_id            = b.matrikel_id
LEFT JOIN [Befordringssystemet].[befordring].[Ungdomsuddannelse]      uu      ON uu.ungdomsuddannelse_id   = b.ungdomsuddannelse_id
LEFT JOIN [Befordringssystemet].[befordring].[Hjemmel]                hjemmel ON hjemmel.hjemmel_id        = b.hjemmel_id
LEFT JOIN [Befordringssystemet].[befordring].[Afgoerelsesbrev]        afg     ON afg.afgoerelsesbrev_id    = b.afgoerelsesbrev_id
LEFT JOIN [Befordringssystemet].[befordring].[Sagsbehandler]          sb      ON sb.sagsbehandler_id       = b.sagsbehandler_id
LEFT JOIN [Befordringssystemet].[befordring].[PPR_Sagsbehandler]      ppr     ON ppr.ppr_sagsbehandler_id  = b.ppr_sagsbehandler_id
LEFT JOIN (
    SELECT
        bhl.bevilling_id,
        STRING_AGG(h.hjaelpemiddel_tekst, ', ') AS hjaelpemidler
    FROM
    [Befordringssystemet].[befordring].[Bevilling_Hjaelpemiddel_LINK] bhl
    INNER JOIN [Befordringssystemet].[befordring].[Hjaelpemiddel]               h
               ON h.hjaelpemiddel_id = bhl.hjaelpemiddel_id
    GROUP BY bhl.bevilling_id
) hjaelpemidler ON hjaelpemidler.bevilling_id = b.bevilling_id
-- A letter should never be built from a deleted bevilling.
WHERE b.aktiv = 1;
GO
/****** Object:  View [befordring].[view_Letter_Koerselsraekker]    Script Date: 14/10/2026 12:53:45 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


CREATE   VIEW [befordring].[view_Letter_Koerselsraekker]
AS
    SELECT
        k.koersel_id,
        k.bevilling_id,

        LOWER(
            REPLACE(
                REPLACE(
                    REPLACE(bt.befordringstype_tekst, 'ø', 'oe'),
                'å', 'aa'),
            ' ', '_')
        ) AS koerselstype_key,

        bt.befordringstype_tekst AS koerselstype,

        t.tidspunkt_tekst AS tidspunkt,

        -- Rutetypen, med lille begyndelsesbogstav: den står midt i en
        -- sætning i afgørelsen ("... bevilges kørsel fra hjem til skole"),
        -- og Befordring har bedt om små bogstaver DÉR. Kun her — i UI'et
        -- står den med stort, som den er gemt. Ét sted at rette navnet.
        LOWER(LEFT(rt.rutetype_tekst, 1)) + SUBSTRING(rt.rutetype_tekst, 2, LEN(rt.rutetype_tekst))
            AS rutetype,

        -- Tie-break under datosorteringen nedenfor. NULL sorterer sidst.
        rt.sorteringsorden AS rutetype_sortering,

        CONVERT(varchar(10), k.gyldig_fra, 105) AS bevilling_fra,
        CONVERT(varchar(10), k.gyldig_til, 105) AS bevilling_til,

        -- Datoerne igen, usorterede og uformaterede, så de kan sorteres på.
        -- bevilling_fra/_til ovenfor er varchar i dd-mm-yyyy: sorteret som
        -- tekst ville de ligge i dag-i-måneden-rækkefølge. De to her når
        -- ikke ud i brevet — get_letter_data kopierer felter ved navn.
        k.gyldig_fra,
        k.gyldig_til,

        k.bevilget_koereafstand_pr_vej,
        k.taxa_id,

        k.transporttid_i_bus,
        k.skift_med_bus,

        -- Taxa-specific. koersel_til_institution is resolved to Ja/Nej here
        -- rather than shipped as a BIT: everything this view exposes drops
        -- straight into letter text, and a raw bit arrives in the RPA as
        -- Python True/False.
        CASE
            WHEN k.koersel_til_institution = 1 THEN N'Ja'
            WHEN k.koersel_til_institution = 0 THEN N'Nej'
            ELSE NULL
        END AS koersel_til_institution,
        k.max_minutter_i_transport,

        -- Egenbefordring-specific: who the kørselsgodtgørelse is paid to.
        -- Resolved to name and CPR, not the id — the id means nothing in a
        -- letter, and this view resolves ids to text everywhere else
        -- (befordringstype_tekst, tidspunkt_tekst, dage).
        --
        -- The recipient lives in one of two mutually exclusive columns:
        --   koerselsgodtgoerelse_modtager_id  -> Part      (øvrig part)
        --   koerselsgodtgoerelse_modtager_cpr -> Foraelder (legal guardian)
        -- so both are COALESCEd, exactly as view_Koerselsgodtgoerelse_Modtagere
        -- does. Only the Part branch was resolved before, which left every
        -- parent recipient blank in the letter.
        COALESCE(foraelder.adresseringsnavn, modtager.fulde_navn)
            AS koerselsgodtgoerelse_modtager,
        COALESCE(foraelder.cpr_foraelder, modtager.cpr_nummer)
            AS koerselsgodtgoerelse_modtager_cpr,

        dage.dage,
        tillaeg.koerselstype_tillaeg
    FROM
        [Befordringssystemet].[befordring].[Koersel] k
    LEFT JOIN
        [Befordringssystemet].[befordring].[Befordringstype] bt
        ON bt.befordringstype_id = k.befordringstype_id
    LEFT JOIN
        [Befordringssystemet].[befordring].[Tidspunkt] t
        ON t.tidspunkt_id = k.tidspunkt_id
    LEFT JOIN
        [Befordringssystemet].[befordring].[Rutetype] rt
        ON rt.rutetype_id = k.rutetype_id
    LEFT JOIN (
        SELECT
            kud.koersel_id,
            STRING_AGG(u.dag_tekst, ', ') AS dage
        FROM
            [Befordringssystemet].[befordring].[Koersel_Ugedag_LINK] kud
        INNER JOIN
            [Befordringssystemet].[befordring].[Ugedag] u
            ON u.dag_id = kud.dag_id
        GROUP BY
            kud.koersel_id
    ) dage
        ON dage.koersel_id = k.koersel_id
    LEFT JOIN (
        SELECT
            ktt_link.koersel_id,
            STRING_AGG(ktt.tillaeg_tekst, ', ') AS koerselstype_tillaeg
        FROM
            [Befordringssystemet].[befordring].[Koersel_KoerselstypeTillaeg_LINK] ktt_link
        INNER JOIN
            [Befordringssystemet].[befordring].[KoerselstypeTillaeg] ktt
            ON ktt.tillaeg_id = ktt_link.tillaeg_id
        GROUP BY
            ktt_link.koersel_id
    ) tillaeg
        ON tillaeg.koersel_id = k.koersel_id
    LEFT JOIN
        [Befordringssystemet].[befordring].[Part] modtager
        ON modtager.part_id = k.koerselsgodtgoerelse_modtager_id
    -- Foraelder is keyed on (cpr_foraelder, cpr_elev), so BOTH halves are
    -- matched. On cpr_foraelder alone a parent with two children in the system
    -- would multiply this kørselsrække into two rows, and the letter would
    -- list it twice.
    LEFT JOIN
        [Befordringssystemet].[befordring].[Bevilling] bev
        ON bev.bevilling_id = k.bevilling_id
    LEFT JOIN
        [Befordringssystemet].[befordring].[Foraelder] foraelder
        ON  foraelder.cpr_foraelder = k.koerselsgodtgoerelse_modtager_cpr
        AND foraelder.cpr_elev      = bev.cpr_elev
-- A deleted kørselsrække must never reach a decision letter.
WHERE
    k.aktiv = 1;
GO
/****** Object:  View [befordring].[view_Applications]    Script Date: 14/10/2026 12:53:45 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


CREATE   VIEW [befordring].[view_Applications]
AS
SELECT
    form_id,
    form_sid,
    form_type,
    form_source,
    form_submitted_date,
    destination_system,
    status,
    response,
    documented_date,
    form_data,
    last_time_modified
FROM
    RPA.journalizing.view_Journalizing
WHERE
    form_type IN (
        'ny_ansoegning_om_koersel_af_skol',
        'ny_ansoegning_om_midlertidig_koe'
    );
GO
/****** Object:  Table [befordring].[Adresse_STG]    Script Date: 14/10/2026 12:53:45 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [befordring].[Adresse_STG](
	[stage_id] [bigint] IDENTITY(1,1) NOT NULL,
	[load_id] [uniqueidentifier] NOT NULL,
	[adresse_id] [nvarchar](36) NOT NULL,
	[adresse_tekst] [nvarchar](500) NULL,
	[latitude] [float] NULL,
	[longitude] [float] NULL,
	[loaded_at] [datetime2](0) NOT NULL,
PRIMARY KEY CLUSTERED 
(
	[stage_id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [befordring].[Elev_Adresse_STG]    Script Date: 14/10/2026 12:53:45 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [befordring].[Elev_Adresse_STG](
	[load_id] [uniqueidentifier] NOT NULL,
	[cpr] [varchar](10) NOT NULL,
	[adresse_id] [nvarchar](36) NOT NULL,
	[loaded_at] [datetime2](0) NOT NULL
) ON [PRIMARY]
GO
/****** Object:  Table [befordring].[Elev_STG]    Script Date: 14/10/2026 12:53:45 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [befordring].[Elev_STG](
	[cpr] [varchar](10) NULL,
	[adresselinjesnavn] [varchar](max) NULL,
	[navne_adresse_beskyttelse] [bit] NULL,
	[skoleafstand] [float] NULL,
	[klasseart] [varchar](max) NULL,
	[elevklassetrin] [varchar](max) NULL,
	[klassebetegnelse] [varchar](max) NULL,
	[institution] [varchar](max) NULL,
	[bopaelsdistrikt] [varchar](max) NULL,
	[matrikel_id] [int] NULL,
	[ungdomsuddannelse_id] [int] NULL,
	[skolekode] [int] NULL,
	[kraever_genberegning] [bit] NULL,
	[adresse_id] [varchar](36) NULL
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
/****** Object:  Table [befordring].[Foraelder_STG]    Script Date: 14/10/2026 12:53:45 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [befordring].[Foraelder_STG](
	[cpr_foraelder] [varchar](10) NULL,
	[cpr_elev] [varchar](10) NULL,
	[adresseringsnavn] [varchar](max) NULL,
	[navne_adresse_beskyttelse] [bit] NULL,
	[maa_vide_barns_adresse] [bit] NULL,
	[adresse_id] [nvarchar](36) NULL,
	[relation] [varchar](50) NULL
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
/****** Object:  Table [befordring].[PortalAuditLog]    Script Date: 14/10/2026 12:53:45 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [befordring].[PortalAuditLog](
	[AuditLogId] [int] IDENTITY(1,1) NOT NULL,
	[BrugerIdent] [nvarchar](200) NULL,
	[IpAdresse] [nvarchar](50) NULL,
	[UserAgent] [nvarchar](500) NULL,
	[OprettetDato] [datetime2](7) NOT NULL,
	[Method] [nvarchar](10) NULL,
	[Path] [nvarchar](500) NULL,
	[QueryParams] [nvarchar](max) NULL,
	[StatusCode] [int] NULL,
	[DurationMs] [decimal](10, 2) NULL,
	[ErrorMessage] [nvarchar](max) NULL,
	[ApiKeyId] [int] NULL,
	[ApiKeyName] [nvarchar](200) NULL,
	[Action] [nvarchar](200) NULL,
 CONSTRAINT [PK_PortalAuditLog] PRIMARY KEY CLUSTERED 
(
	[AuditLogId] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
/****** Object:  Table [befordring].[Sagsaktivitet]    Script Date: 14/10/2026 12:53:45 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [befordring].[Sagsaktivitet](
	[aktivitet_id] [int] IDENTITY(1,1) NOT NULL,
	[cpr] [varchar](10) NOT NULL,
	[aktivitetstype] [varchar](50) NOT NULL,
	[kommentar] [nvarchar](max) NULL,
	[udfoert_af] [varchar](100) NULL,
	[oprettet_tidspunkt] [datetime2](7) NOT NULL,
	[relateret_bevilling_id] [int] NULL,
	[aktivitetstype_id] [int] NULL,
PRIMARY KEY CLUSTERED 
(
	[aktivitet_id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
/****** Object:  Table [befordring].[SagsaktivitetType]    Script Date: 14/10/2026 12:53:45 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [befordring].[SagsaktivitetType](
	[type_id] [int] IDENTITY(1,1) NOT NULL,
	[type_kode] [nvarchar](100) NOT NULL,
 CONSTRAINT [PK_SagsaktivitetType] PRIMARY KEY CLUSTERED 
(
	[type_id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY],
 CONSTRAINT [UQ_SagsaktivitetType_kode] UNIQUE NONCLUSTERED 
(
	[type_kode] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO
ALTER TABLE [befordring].[Adresse_STG] ADD  CONSTRAINT [DF_Adresse_Stage_loaded_at]  DEFAULT (sysutcdatetime()) FOR [loaded_at]
GO
ALTER TABLE [befordring].[Bevilling] ADD  DEFAULT (sysdatetime()) FOR [created_at]
GO
ALTER TABLE [befordring].[Bevilling] ADD  DEFAULT (sysdatetime()) FOR [updated_at]
GO
ALTER TABLE [befordring].[Bevilling] ADD  CONSTRAINT [DF_Bevilling_final]  DEFAULT ((0)) FOR [final]
GO
ALTER TABLE [befordring].[Brev] ADD  CONSTRAINT [DF_Brev_oprettet_tidspunkt]  DEFAULT (sysdatetime()) FOR [oprettet_tidspunkt]
GO
ALTER TABLE [befordring].[Brev] ADD  CONSTRAINT [DF_Brev_afsendt]  DEFAULT ((0)) FOR [afsendt]
GO
ALTER TABLE [befordring].[Brev] ADD  CONSTRAINT [DF_Brev_aktiv]  DEFAULT ((1)) FOR [aktiv]
GO
ALTER TABLE [befordring].[Elev] ADD  CONSTRAINT [DF_Elev_Skolekode]  DEFAULT ((0)) FOR [skolekode]
GO
ALTER TABLE [befordring].[Elev] ADD  DEFAULT ((0)) FOR [kraever_genberegning]
GO
ALTER TABLE [befordring].[Elev_Adresse_STG] ADD  CONSTRAINT [DF_Elev_Adresse_STG_loaded_at]  DEFAULT (sysutcdatetime()) FOR [loaded_at]
GO
ALTER TABLE [befordring].[Foraelder] ADD  CONSTRAINT [DF_Foraelder_maa_vide_barns_adresse]  DEFAULT ((1)) FOR [maa_vide_barns_adresse]
GO
ALTER TABLE [befordring].[Foraelder] ADD  CONSTRAINT [DF_Foraelder_relation]  DEFAULT ('Ukendt') FOR [relation]
GO
ALTER TABLE [befordring].[Koersel] ADD  CONSTRAINT [DF_Koersel_aktiv]  DEFAULT ((1)) FOR [aktiv]
GO
ALTER TABLE [befordring].[Part] ADD  CONSTRAINT [DF_Part_oprettet]  DEFAULT (sysdatetime()) FOR [oprettet_tidspunkt]
GO
ALTER TABLE [befordring].[Part] ADD  CONSTRAINT [DF_Part_aktiv]  DEFAULT ((1)) FOR [aktiv]
GO
ALTER TABLE [befordring].[Rutetype] ADD  CONSTRAINT [DF_Rutetype_aktiv]  DEFAULT ((1)) FOR [aktiv]
GO
ALTER TABLE [befordring].[Sagsaktivitet] ADD  DEFAULT (getdate()) FOR [oprettet_tidspunkt]
GO
ALTER TABLE [befordring].[Bevilling]  WITH CHECK ADD  CONSTRAINT [FK_Bevilling_Adresse] FOREIGN KEY([adresse_id])
REFERENCES [befordring].[Adresse] ([adresse_id])
GO
ALTER TABLE [befordring].[Bevilling] CHECK CONSTRAINT [FK_Bevilling_Adresse]
GO
ALTER TABLE [befordring].[Bevilling]  WITH CHECK ADD  CONSTRAINT [FK_bevilling_afgoerelsesbrev] FOREIGN KEY([afgoerelsesbrev_id])
REFERENCES [befordring].[Afgoerelsesbrev] ([afgoerelsesbrev_id])
GO
ALTER TABLE [befordring].[Bevilling] CHECK CONSTRAINT [FK_bevilling_afgoerelsesbrev]
GO
ALTER TABLE [befordring].[Bevilling]  WITH CHECK ADD  CONSTRAINT [FK_Bevilling_AnsvarligPprSagsbehandler] FOREIGN KEY([ansvarlig_ppr_sagsbehandler_id])
REFERENCES [befordring].[PPR_Sagsbehandler] ([ppr_sagsbehandler_id])
GO
ALTER TABLE [befordring].[Bevilling] CHECK CONSTRAINT [FK_Bevilling_AnsvarligPprSagsbehandler]
GO
ALTER TABLE [befordring].[Bevilling]  WITH CHECK ADD  CONSTRAINT [FK_Bevilling_AnsvarligSagsbehandler] FOREIGN KEY([ansvarlig_sagsbehandler_id])
REFERENCES [befordring].[Sagsbehandler] ([sagsbehandler_id])
GO
ALTER TABLE [befordring].[Bevilling] CHECK CONSTRAINT [FK_Bevilling_AnsvarligSagsbehandler]
GO
ALTER TABLE [befordring].[Bevilling]  WITH CHECK ADD  CONSTRAINT [FK_bevilling_elev_cpr] FOREIGN KEY([cpr_elev])
REFERENCES [befordring].[Elev] ([cpr])
GO
ALTER TABLE [befordring].[Bevilling] CHECK CONSTRAINT [FK_bevilling_elev_cpr]
GO
ALTER TABLE [befordring].[Bevilling]  WITH CHECK ADD  CONSTRAINT [FK_bevilling_hjemmel] FOREIGN KEY([hjemmel_id])
REFERENCES [befordring].[Hjemmel] ([hjemmel_id])
GO
ALTER TABLE [befordring].[Bevilling] CHECK CONSTRAINT [FK_bevilling_hjemmel]
GO
ALTER TABLE [befordring].[Bevilling]  WITH CHECK ADD  CONSTRAINT [FK_bevilling_matrikel] FOREIGN KEY([matrikel_id])
REFERENCES [befordring].[Skolematrikel] ([matrikel_id])
GO
ALTER TABLE [befordring].[Bevilling] CHECK CONSTRAINT [FK_bevilling_matrikel]
GO
ALTER TABLE [befordring].[Bevilling]  WITH CHECK ADD  CONSTRAINT [FK_bevilling_ppr_sagsbehandler] FOREIGN KEY([ppr_sagsbehandler_id])
REFERENCES [befordring].[PPR_Sagsbehandler] ([ppr_sagsbehandler_id])
GO
ALTER TABLE [befordring].[Bevilling] CHECK CONSTRAINT [FK_bevilling_ppr_sagsbehandler]
GO
ALTER TABLE [befordring].[Bevilling]  WITH CHECK ADD  CONSTRAINT [FK_bevilling_sagsbehandler] FOREIGN KEY([sagsbehandler_id])
REFERENCES [befordring].[Sagsbehandler] ([sagsbehandler_id])
GO
ALTER TABLE [befordring].[Bevilling] CHECK CONSTRAINT [FK_bevilling_sagsbehandler]
GO
ALTER TABLE [befordring].[Bevilling]  WITH CHECK ADD  CONSTRAINT [FK_bevilling_status] FOREIGN KEY([status_id])
REFERENCES [befordring].[Status] ([status_id])
GO
ALTER TABLE [befordring].[Bevilling] CHECK CONSTRAINT [FK_bevilling_status]
GO
ALTER TABLE [befordring].[Bevilling]  WITH CHECK ADD  CONSTRAINT [FK_Bevilling_Ungdomsuddannelse] FOREIGN KEY([ungdomsuddannelse_id])
REFERENCES [befordring].[Ungdomsuddannelse] ([ungdomsuddannelse_id])
GO
ALTER TABLE [befordring].[Bevilling] CHECK CONSTRAINT [FK_Bevilling_Ungdomsuddannelse]
GO
ALTER TABLE [befordring].[Bevilling_Hjaelpemiddel_LINK]  WITH CHECK ADD  CONSTRAINT [FK_Bevilling_Hjaelpemiddel_LINK_Hjaelpemiddel] FOREIGN KEY([hjaelpemiddel_id])
REFERENCES [befordring].[Hjaelpemiddel] ([hjaelpemiddel_id])
GO
ALTER TABLE [befordring].[Bevilling_Hjaelpemiddel_LINK] CHECK CONSTRAINT [FK_Bevilling_Hjaelpemiddel_LINK_Hjaelpemiddel]
GO
ALTER TABLE [befordring].[Bevilling_Hjaelpemiddel_LINK]  WITH CHECK ADD  CONSTRAINT [FK_Bevilling_Hjaelpemiddel_LINK_Koersel] FOREIGN KEY([bevilling_id])
REFERENCES [befordring].[Bevilling] ([bevilling_id])
GO
ALTER TABLE [befordring].[Bevilling_Hjaelpemiddel_LINK] CHECK CONSTRAINT [FK_Bevilling_Hjaelpemiddel_LINK_Koersel]
GO
ALTER TABLE [befordring].[Brev]  WITH CHECK ADD  CONSTRAINT [FK_Brev_Bevilling] FOREIGN KEY([bevilling_id])
REFERENCES [befordring].[Bevilling] ([bevilling_id])
GO
ALTER TABLE [befordring].[Brev] CHECK CONSTRAINT [FK_Brev_Bevilling]
GO
ALTER TABLE [befordring].[Elev]  WITH CHECK ADD  CONSTRAINT [FK_Elev_Adresse] FOREIGN KEY([adresse_id])
REFERENCES [befordring].[Adresse] ([adresse_id])
GO
ALTER TABLE [befordring].[Elev] CHECK CONSTRAINT [FK_Elev_Adresse]
GO
ALTER TABLE [befordring].[Elev]  WITH CHECK ADD  CONSTRAINT [FK_Elev_Skolematrikel] FOREIGN KEY([matrikel_id])
REFERENCES [befordring].[Skolematrikel] ([matrikel_id])
GO
ALTER TABLE [befordring].[Elev] CHECK CONSTRAINT [FK_Elev_Skolematrikel]
GO
ALTER TABLE [befordring].[Elev]  WITH CHECK ADD  CONSTRAINT [FK_Elev_Ungdomsuddannelse] FOREIGN KEY([ungdomsuddannelse_id])
REFERENCES [befordring].[Ungdomsuddannelse] ([ungdomsuddannelse_id])
GO
ALTER TABLE [befordring].[Elev] CHECK CONSTRAINT [FK_Elev_Ungdomsuddannelse]
GO
ALTER TABLE [befordring].[Foraelder]  WITH CHECK ADD  CONSTRAINT [FK_Foraelder_Adresse] FOREIGN KEY([adresse_id])
REFERENCES [befordring].[Adresse] ([adresse_id])
GO
ALTER TABLE [befordring].[Foraelder] CHECK CONSTRAINT [FK_Foraelder_Adresse]
GO
ALTER TABLE [befordring].[Foraelder]  WITH CHECK ADD  CONSTRAINT [FK_Foraelder_Elev] FOREIGN KEY([cpr_elev])
REFERENCES [befordring].[Elev] ([cpr])
GO
ALTER TABLE [befordring].[Foraelder] CHECK CONSTRAINT [FK_Foraelder_Elev]
GO
ALTER TABLE [befordring].[Koersel]  WITH CHECK ADD  CONSTRAINT [FK_koersel_befordringstype] FOREIGN KEY([befordringstype_id])
REFERENCES [befordring].[Befordringstype] ([befordringstype_id])
GO
ALTER TABLE [befordring].[Koersel] CHECK CONSTRAINT [FK_koersel_befordringstype]
GO
ALTER TABLE [befordring].[Koersel]  WITH CHECK ADD  CONSTRAINT [FK_koersel_bevilling] FOREIGN KEY([bevilling_id])
REFERENCES [befordring].[Bevilling] ([bevilling_id])
GO
ALTER TABLE [befordring].[Koersel] CHECK CONSTRAINT [FK_koersel_bevilling]
GO
ALTER TABLE [befordring].[Koersel]  WITH CHECK ADD  CONSTRAINT [FK_Koersel_KoerselsgodtgoerelseModtager] FOREIGN KEY([koerselsgodtgoerelse_modtager_id])
REFERENCES [befordring].[Part] ([part_id])
GO
ALTER TABLE [befordring].[Koersel] CHECK CONSTRAINT [FK_Koersel_KoerselsgodtgoerelseModtager]
GO
ALTER TABLE [befordring].[Koersel]  WITH CHECK ADD  CONSTRAINT [FK_Koersel_Rutetype] FOREIGN KEY([rutetype_id])
REFERENCES [befordring].[Rutetype] ([rutetype_id])
GO
ALTER TABLE [befordring].[Koersel] CHECK CONSTRAINT [FK_Koersel_Rutetype]
GO
ALTER TABLE [befordring].[Koersel]  WITH CHECK ADD  CONSTRAINT [FK_koersel_tidspunkt] FOREIGN KEY([tidspunkt_id])
REFERENCES [befordring].[Tidspunkt] ([tidspunkt_id])
GO
ALTER TABLE [befordring].[Koersel] CHECK CONSTRAINT [FK_koersel_tidspunkt]
GO
ALTER TABLE [befordring].[Koersel_KoerselstypeTillaeg_LINK]  WITH CHECK ADD  CONSTRAINT [FK_Koersel_KoerselstypeTillaeg_LINK_Koersel] FOREIGN KEY([koersel_id])
REFERENCES [befordring].[Koersel] ([koersel_id])
GO
ALTER TABLE [befordring].[Koersel_KoerselstypeTillaeg_LINK] CHECK CONSTRAINT [FK_Koersel_KoerselstypeTillaeg_LINK_Koersel]
GO
ALTER TABLE [befordring].[Koersel_KoerselstypeTillaeg_LINK]  WITH CHECK ADD  CONSTRAINT [FK_Koersel_KoerselstypeTillaeg_LINK_KoerselstypeTillaeg] FOREIGN KEY([tillaeg_id])
REFERENCES [befordring].[KoerselstypeTillaeg] ([tillaeg_id])
GO
ALTER TABLE [befordring].[Koersel_KoerselstypeTillaeg_LINK] CHECK CONSTRAINT [FK_Koersel_KoerselstypeTillaeg_LINK_KoerselstypeTillaeg]
GO
ALTER TABLE [befordring].[Koersel_Ugedag_LINK]  WITH CHECK ADD  CONSTRAINT [FK_Koersel_Ugedag_LINK_Koersel] FOREIGN KEY([koersel_id])
REFERENCES [befordring].[Koersel] ([koersel_id])
GO
ALTER TABLE [befordring].[Koersel_Ugedag_LINK] CHECK CONSTRAINT [FK_Koersel_Ugedag_LINK_Koersel]
GO
ALTER TABLE [befordring].[Koersel_Ugedag_LINK]  WITH CHECK ADD  CONSTRAINT [FK_Koersel_Ugedag_LINK_Ugedag] FOREIGN KEY([dag_id])
REFERENCES [befordring].[Ugedag] ([dag_id])
GO
ALTER TABLE [befordring].[Koersel_Ugedag_LINK] CHECK CONSTRAINT [FK_Koersel_Ugedag_LINK_Ugedag]
GO
ALTER TABLE [befordring].[Part]  WITH CHECK ADD  CONSTRAINT [FK_Part_Adresse] FOREIGN KEY([adresse_id])
REFERENCES [befordring].[Adresse] ([adresse_id])
GO
ALTER TABLE [befordring].[Part] CHECK CONSTRAINT [FK_Part_Adresse]
GO
ALTER TABLE [befordring].[Part]  WITH CHECK ADD  CONSTRAINT [FK_Part_Elev] FOREIGN KEY([cpr_elev])
REFERENCES [befordring].[Elev] ([cpr])
GO
ALTER TABLE [befordring].[Part] CHECK CONSTRAINT [FK_Part_Elev]
GO
ALTER TABLE [befordring].[Sagsaktivitet]  WITH CHECK ADD  CONSTRAINT [FK_Sagsaktivitet_Type] FOREIGN KEY([aktivitetstype_id])
REFERENCES [befordring].[SagsaktivitetType] ([type_id])
GO
ALTER TABLE [befordring].[Sagsaktivitet] CHECK CONSTRAINT [FK_Sagsaktivitet_Type]
GO
/****** Object:  StoredProcedure [befordring].[usp_recalculate_bevilling_status]    Script Date: 14/10/2026 12:53:45 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


CREATE   PROCEDURE [befordring].[usp_recalculate_bevilling_status]
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
            e.adresse_id  AS elev_adresse_id,
            e.skolekode   AS elev_skolekode,
            b.genbehandling_haandteret_adresse_id,
            b.genbehandling_haandteret_skolekode
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
            -- Genbehandling flag: mismatch-based (skolekode or adresse drift).
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
                            )
                        )
                        OR
                        -- stay: hold until caseworker marks it handled, but only while
                        -- a mismatch is still live AND the bevilling has an active kørsel.
                        -- Expired bevillinger auto-close rather than requiring caseworker action.
                        (
                            ISNULL(kf.current_genbehandling, 0) = 1
                            AND ISNULL(kf.genbehandling_haandteret, 0) = 0
                            AND (kf.adresse_mismatch = 1 OR kf.skolekode_mismatch = 1)
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
/****** Object:  StoredProcedure [befordring].[usp_sync_elev_matrikel_from_bevilling]    Script Date: 14/10/2026 12:53:45 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/*
    Derive Elev.matrikel_id and Elev.ungdomsuddannelse_id from the student's
    bevillinger.

    Elev_STG carries neither — the data worker's source has no school. The only
    place a school exists is on the bevilling, so it is copied back onto the
    student here.

    Which bevilling:

        * the student's ACTIVE bevilling, if they have a qualifying one
        * otherwise the qualifying bevilling that runs LONGEST — the latest
          gyldig_til across its kørselsrækker

    Soft-deleted bevillinger (aktiv = 0) are ignored throughout.

    What makes a bevilling QUALIFY:

      folkeskole            b.matrikel_id is set, AND that matrikel's skolekode
                            equals the student's own skolekode.

                            The student's skolekode comes from the data
                            worker's load and is the authority on which school
                            the child attends. A bevilling that has not caught
                            up — still pointing at last year's school — must not
                            supply a matrikel, or the walking distance would be
                            measured to a school the child no longer attends.

      ungdomsuddannelse     b.matrikel_id is NULL and b.ungdomsuddannelse_id is
                            set. There is no skolekode on an ungdomsuddannelse,
                            so there is nothing to cross-check; the bevilling is
                            taken at face value.

    Where NOTHING qualifies, both columns are CLEARED — with one exception: a
    matrikel whose skolekode equals the student's own is left alone, because it
    names the school the child is registered at and is therefore not stale. See
    the #Delta filter. That exception is what lets genberegn_skole resolve a
    school for a student who has no bevilling at all, without the next nightly
    run undoing it.

    Otherwise the clearing is the point of the procedure as much as the copying
    is: a stale school is worse than no school. It skips the walking-distance step (which needs coordinates) rather
    than producing a confidently wrong number, and the mismatch is already on
    the Genbehandling page for a caseworker to resolve. Once the bevilling is
    corrected, the next night derives the school again.

    This procedure is AUTHORITATIVE over both columns with that one exception:
    after it runs, they mirror the chosen bevilling, or they hold a matrikel
    that matches the student's own skolekode, or they are NULL.

    What this is for, and what it is NOT for:

      The pair feeds the walking-distance calculation, which resolves school
      coordinates from Skolematrikel or Ungdomsuddannelse. Measuring to the
      bevilling's school is correct: skoleafstand exists to serve the
      afstandskriterie on that bevilling.

      It does NOT feed genbehandling. usp_recalculate_bevilling_status compares
      Elev.SKOLEKODE against the skolekode of the BEVILLING's matrikel — two
      independent sources. Deriving matrikel_id from the bevilling cannot mask
      a mismatch, because the qualifying rule above means a mismatched bevilling
      never supplies one in the first place.

    kraever_genberegning is raised wherever the pair actually changes, cleared
    or set, because the school the distance is measured to has moved. The other
    two triggers live with the columns they belong to — skolekode in
    usp_upsert_elev_from_stg, adresse_id in usp_upsert_adresse_ids_from_stg.

    Ordering: run AFTER usp_upsert_elev_from_stg, so that new students exist to
    match against and skolekode is already current.
*/

CREATE   PROCEDURE [befordring].[usp_sync_elev_matrikel_from_bevilling]
    /* Narrow the sync to one student. NULL (the default) syncs everyone, which
       is what the nightly run does.

       Passing a cpr makes this the same authoritative derivation, applied to
       one row, so a caseworker can resolve a single student on demand rather
       than waiting for the night. Same precedent as @bevilling_id on
       usp_recalculate_bevilling_status. The rules are not duplicated or
       relaxed for the single-student case — it is the same code path. */
    @cpr CHAR(10) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @qualifying  INT = 0;
    DECLARE @changed     INT = 0;
    DECLARE @cleared     INT = 0;

    BEGIN TRY
        BEGIN TRANSACTION;

            /* Bevillinger that may supply a school for their student. */
            ;WITH Qualifying AS
            (
                SELECT
                    b.cpr_elev,
                    b.matrikel_id,
                    b.ungdomsuddannelse_id,
                    b.created_at,
                    b.bevilling_id,
                    CASE WHEN s.status_tekst = N'Aktiv' THEN 0 ELSE 1 END AS status_rank,
                    kr.seneste_gyldig_til
                FROM       [befordring].[Bevilling]      b
                LEFT JOIN  [befordring].[Status]         s  ON s.status_id   = b.status_id
                /* The last day this bevilling covers anyone. A bevilling is a
                   container; its kørselsrækker carry the dates, so "which
                   bevilling runs longest" can only be asked of them. Soft-
                   deleted rækker are excluded for the same reason
                   soft-deleted bevillinger are. */
                OUTER APPLY (
                    SELECT MAX(k.gyldig_til) AS seneste_gyldig_til
                    FROM   [befordring].[Koersel] k
                    WHERE  k.bevilling_id = b.bevilling_id
                    AND    k.aktiv = 1
                ) kr
                INNER JOIN [befordring].[Elev]           e  ON e.cpr         = b.cpr_elev
                LEFT JOIN  [befordring].[Skolematrikel]  sm ON sm.matrikel_id = b.matrikel_id
                WHERE b.aktiv = 1
                AND (@cpr IS NULL OR b.cpr_elev = @cpr)
                AND (
                        /* folkeskole: the matrikel must belong to the school
                           the child is actually registered at. */
                        (
                            b.matrikel_id IS NOT NULL
                            AND ISNULL(e.skolekode, 0) <> 0
                            AND sm.skolekode = e.skolekode
                        )
                        OR
                        /* ungdomsuddannelse: no skolekode exists to check. */
                        (
                            b.matrikel_id IS NULL
                            AND b.ungdomsuddannelse_id IS NOT NULL
                        )
                    )
            ),
            /* rank 0 sorts before 1, so an Aktiv bevilling wins regardless of
               anything else. That is the whole rule where a student has one:
               the school they are being driven to today is the school they
               attend.

               Where none is Aktiv, the one running LONGEST wins — the latest
               gyldig_til across its kørselsrækker. That used to be created_at
               DESC, which asked when the row was typed rather than what it
               describes: a bevilling entered last week for a period that
               ended two years ago outranked one still running next term, and
               the student was derived to the school they have already left.

               A bevilling with no kørselsrækker at all has no period, so it
               sorts last of the non-Aktiv ones and only supplies a school
               when nothing else can. created_at and bevilling_id then break
               the remaining ties, so the choice is stable from one night to
               the next rather than arbitrary. */
            Ranked AS
            (
                SELECT
                    cpr_elev,
                    matrikel_id,
                    ungdomsuddannelse_id,
                    ROW_NUMBER() OVER (
                        PARTITION BY cpr_elev
                        ORDER BY     status_rank,
                                     CASE WHEN seneste_gyldig_til IS NULL THEN 1 ELSE 0 END,
                                     seneste_gyldig_til DESC,
                                     created_at DESC,
                                     bevilling_id DESC
                    ) AS rn
                FROM Qualifying
            )
            SELECT cpr_elev, matrikel_id, ungdomsuddannelse_id
            INTO   #Chosen
            FROM   Ranked
            WHERE  rn = 1;

            CREATE UNIQUE CLUSTERED INDEX IX_Chosen_cpr ON #Chosen (cpr_elev);

            SELECT @qualifying = COUNT(*) FROM #Chosen;

            /* Every student is considered, not just those with a chosen
               bevilling: the LEFT JOIN yields NULLs where nothing qualifies,
               which is exactly the value that should be written.

               EXCEPT rather than "<>" so NULL compares equal to NULL — a
               student who has no school and should have none is not rewritten,
               and does not have kraever_genberegning raised, every night. */
            SELECT
                e.cpr,
                c.matrikel_id,
                c.ungdomsuddannelse_id,
                CASE WHEN c.cpr_elev IS NULL THEN 1 ELSE 0 END AS is_clear
            INTO      #Delta
            FROM      [befordring].[Elev] e
            LEFT JOIN #Chosen c ON c.cpr_elev = e.cpr
            /* Only students who could possibly change: they have a
               qualifying bevilling, or they carry a school that may now need
               clearing. A student with neither has NULL on both sides, the
               EXCEPT below yields nothing, and the row can never reach
               #Delta — so excluding it here changes no result.

               It matters because Elev now holds every student in the
               municipality, not only those with a bevilling. The vast
               majority fall in that third group, and without this the delta
               is computed across the whole table every night to produce
               nothing for them. */
            WHERE (@cpr IS NULL OR e.cpr = @cpr)
              AND (
                      c.cpr_elev             IS NOT NULL
                   OR e.matrikel_id          IS NOT NULL
                   OR e.ungdomsuddannelse_id IS NOT NULL
                  )
              /* Do not clear a school that is not stale.

                 No bevilling qualifies, but the matrikel already on the
                 student belongs to the very skolekode the student is
                 registered at — so it names the right school, whatever the
                 bevillinger do or do not say. genberegn_skole resolves exactly
                 this where a skolekode has only one matrikel, and without this
                 the next nightly run would wipe it.

                 "Stale" has always meant "points at a school the child does
                 not attend", and skolekode is this procedure's own stated
                 authority on which school that is. A matrikel agreeing with it
                 cannot be stale by that definition.

                 A real school change is still caught, and earlier:
                 usp_upsert_elev_from_stg clears matrikel_id, skoleafstand and
                 ungdomsuddannelse_id the moment the skolekode moves, so by the
                 time this runs there is nothing left to protect.

                 ungdomsuddannelse_id must be NULL for the protection to apply.
                 The pair is written from one bevilling and is therefore always
                 (matrikel, NULL) or (NULL, ungdomsuddannelse); should both ever
                 be set, the row is not protected and is cleared as before. */
              AND NOT (
                      c.cpr_elev             IS NULL
                  AND e.matrikel_id          IS NOT NULL
                  AND e.ungdomsuddannelse_id IS NULL
                  AND ISNULL(e.skolekode, 0) <> 0
                  AND EXISTS (
                          SELECT 1
                          FROM   [befordring].[Skolematrikel] sm
                          WHERE  sm.matrikel_id = e.matrikel_id
                          AND    sm.skolekode   = e.skolekode
                      )
                  )
              AND EXISTS (
                      SELECT e.matrikel_id, e.ungdomsuddannelse_id
                      EXCEPT
                      SELECT c.matrikel_id, c.ungdomsuddannelse_id
                  );

            SELECT
                @changed = COUNT(*),
                @cleared = SUM(CASE WHEN is_clear = 1 THEN 1 ELSE 0 END)
            FROM #Delta;

            UPDATE e
            SET    e.matrikel_id          = d.matrikel_id,
                   e.ungdomsuddannelse_id = d.ungdomsuddannelse_id,
                   e.kraever_genberegning = 1
            FROM   [befordring].[Elev] e
            JOIN   #Delta d ON d.cpr = e.cpr;

        COMMIT TRANSACTION;

        SELECT
            @qualifying        AS students_with_qualifying_bevilling,
            @changed           AS school_changed,
            ISNULL(@cleared,0) AS of_which_cleared;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH;
END;
GO
/****** Object:  StoredProcedure [befordring].[usp_upsert_adresse_ids_from_stg]    Script Date: 14/10/2026 12:53:45 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/*
    Resolve adresse_id for elever and forældre from Elev_Adresse_STG.

    Elev_STG and Foraelder_STG never carry an address — the data worker's job
    does not have one. The link between a person and an address comes from
    LOIS.CPR.PersonGeoView instead, which the RPA loads into Elev_Adresse_STG
    keyed on PNR_0 (ten digits, no dash, matching Elev.cpr and
    Foraelder.cpr_foraelder).

    One stage serves both tables: the column is `cpr`, not `cpr_elev`, so a
    guardian's row looks exactly like a student's.

    This procedure owns Elev.adresse_id. It is therefore also what raises
    kraever_genberegning when a student moves, since a new address changes the
    distance to school. usp_upsert_elev_from_stg raises the flag for the other
    half — a change of school.

    Addresses not present in Adresse are skipped, not written. Elev's and
    Foraelder's foreign keys to Adresse are trusted (migration 021), so writing
    an unknown id would fail the whole batch; and an address the nightly
    Adresse import has not loaded yet is a sequencing problem, not a reason to
    lose the rest of the run. The skipped count is returned so a persistent
    gap is visible.

    Ordering: this must run AFTER usp_upsert_adresser_from_stg (so Adresse is
    current) and AFTER usp_upsert_elev_from_stg (so new students exist to
    match).
*/

CREATE   PROCEDURE [befordring].[usp_upsert_adresse_ids_from_stg]
    @load_id                UNIQUEIDENTIFIER,
    @clear_stage_afterwards BIT = 1,
    -- See usp_upsert_adresser_from_stg: one nightly run, so a load older than
    -- a day belongs to a run that never finished.
    @stale_after_days       INT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @staged_rows       INT = 0;
    DECLARE @orphans_swept     INT = 0;
    DECLARE @unknown_adresse   INT = 0;
    DECLARE @elev_updated      INT = 0;
    DECLARE @foraelder_updated INT = 0;

    BEGIN TRY
        BEGIN TRANSACTION;

            /* Sweep orphaned loads.

               A run that fails while staging never reaches this procedure, so
               its rows are never deleted by the load_id clear below. They are
               invisible to every consumer — all of which filter on load_id —
               but they accumulate, and nothing else ever reaps them.

               Bounded by age rather than "anything that is not this load", so
               two runs overlapping cannot delete each other's rows mid-flight.
               Never touches the current load: its rows were staged moments
               ago. */
            DELETE FROM [befordring].[Elev_Adresse_STG]
            WHERE load_id <> @load_id
            AND   loaded_at < DATEADD(DAY, -@stale_after_days, SYSUTCDATETIME());

            SET @orphans_swept = @@ROWCOUNT;

            /* One row per cpr for this load. A person appears once in
               PersonGeoView, but the stage has no key to enforce it. */
            ;WITH SourceRows AS
            (
                SELECT
                    LTRIM(RTRIM(cpr))        AS cpr,
                    LTRIM(RTRIM(adresse_id)) AS adresse_id,
                    ROW_NUMBER() OVER (
                        PARTITION BY LTRIM(RTRIM(cpr))
                        ORDER BY     (SELECT NULL)
                    ) AS rn
                FROM [befordring].[Elev_Adresse_STG]
                WHERE load_id = @load_id
                AND   NULLIF(LTRIM(RTRIM(cpr)), '')        IS NOT NULL
                AND   NULLIF(LTRIM(RTRIM(adresse_id)), '') IS NOT NULL
            )
            SELECT cpr, adresse_id
            INTO   #Source
            FROM   SourceRows
            WHERE  rn = 1;

            SELECT @staged_rows = COUNT(*) FROM #Source;

            /* Drop anything Adresse does not know about, rather than letting
               the foreign key take the whole transaction down. */
            SELECT @unknown_adresse = COUNT(*)
            FROM   #Source s
            WHERE  NOT EXISTS (SELECT 1 FROM [befordring].[Adresse] a
                               WHERE a.adresse_id = s.adresse_id);

            DELETE s
            FROM   #Source s
            WHERE  NOT EXISTS (SELECT 1 FROM [befordring].[Adresse] a
                               WHERE a.adresse_id = s.adresse_id);

            CREATE UNIQUE CLUSTERED INDEX IX_Source_cpr ON #Source (cpr);

            /* Students who are actually moving. Captured before the UPDATE,
               while the old adresse_id is still readable. ISNULL guards the
               first-ever resolution, where the current value is NULL. */
            SELECT e.cpr
            INTO   #Moved
            FROM   [befordring].[Elev] e
            JOIN   #Source s ON s.cpr = e.cpr
            WHERE  ISNULL(e.adresse_id, '') <> s.adresse_id;

            UPDATE e
            SET    e.adresse_id = s.adresse_id
            FROM   [befordring].[Elev] e
            JOIN   #Source s ON s.cpr = e.cpr
            WHERE  ISNULL(e.adresse_id, '') <> s.adresse_id;

            SET @elev_updated = @@ROWCOUNT;

            /* A new address moves the child relative to their school, so the
               walking distance has to be recalculated. */
            UPDATE e
            SET    e.kraever_genberegning = 1
            FROM   [befordring].[Elev] e
            JOIN   #Moved m ON m.cpr = e.cpr;

            /* Guardians are matched on their own CPR, so one row in the stage
               updates every Foraelder row that adult has — one per child. */
            UPDATE f
            SET    f.adresse_id = s.adresse_id
            FROM   [befordring].[Foraelder] f
            JOIN   #Source s ON s.cpr = f.cpr_foraelder
            WHERE  ISNULL(f.adresse_id, '') <> s.adresse_id;

            SET @foraelder_updated = @@ROWCOUNT;

            IF @clear_stage_afterwards = 1
            BEGIN
                DELETE FROM [befordring].[Elev_Adresse_STG]
                WHERE load_id = @load_id;
            END;

        COMMIT TRANSACTION;

        SELECT
            @staged_rows       AS staged_rows,
            @unknown_adresse   AS skipped_unknown_adresse,
            @elev_updated      AS elev_updated,
            @foraelder_updated AS foraelder_updated,
            @orphans_swept     AS orphan_rows_swept;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH;
END;
GO
/****** Object:  StoredProcedure [befordring].[usp_upsert_adresser_from_stg]    Script Date: 14/10/2026 12:53:45 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


CREATE   PROCEDURE [befordring].[usp_upsert_adresser_from_stg]
    @load_id UNIQUEIDENTIFIER,
    @clear_stage_afterwards BIT = 1,
    -- How long a staged load may survive before it is treated as debris from
    -- a failed run. One day: the job runs nightly, so anything older than that
    -- belongs to a run that never finished.
    @stale_after_days INT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @updated_rows INT = 0;
    DECLARE @inserted_rows INT = 0;
    DECLARE @staged_rows INT = 0;
    DECLARE @orphans_swept INT = 0;

    BEGIN TRY
        BEGIN TRANSACTION;

            /* Sweep orphaned loads.

               A run that fails while staging never reaches this procedure, so
               its rows are never deleted by the load_id clear below. They are
               invisible to every consumer — all of which filter on load_id —
               but they accumulate, and Adresse_STG stages every address in
               the municipality.

               Bounded by age rather than "anything that is not this load", so
               two runs overlapping cannot delete each other's rows mid-flight.
               Never touches the current load: its rows were staged moments
               ago. */
            DELETE FROM [befordring].[Adresse_STG]
            WHERE load_id <> @load_id
            AND   loaded_at < DATEADD(DAY, -@stale_after_days, SYSUTCDATETIME());

            SET @orphans_swept = @@ROWCOUNT;

            ;WITH SourceRows AS
            (
                SELECT
                    adresse_id,
                    adresse_tekst,
                    latitude,
                    longitude,
                    ROW_NUMBER() OVER (
                        PARTITION BY adresse_id
                        ORDER BY stage_id DESC
                    ) AS rn
                FROM [befordring].[Adresse_STG]
                WHERE load_id = @load_id
            )
            SELECT
                adresse_id,
                adresse_tekst,
                latitude,
                longitude
            INTO #SourceDeduplicated
            FROM SourceRows
            WHERE rn = 1;

            CREATE UNIQUE CLUSTERED INDEX IX_SourceDeduplicated_adresse_id
            ON #SourceDeduplicated (adresse_id);

            SELECT
                @staged_rows = COUNT(*)
            FROM #SourceDeduplicated;


            UPDATE target
            SET
                target.adresse_tekst = source.adresse_tekst,
                target.latitude = source.latitude,
                target.longitude = source.longitude
            FROM [befordring].[Adresse] target
            JOIN #SourceDeduplicated source
                ON source.adresse_id = target.adresse_id
            WHERE EXISTS
            (
                SELECT
                    target.adresse_tekst,
                    target.latitude,
                    target.longitude

                EXCEPT

                SELECT
                    source.adresse_tekst,
                    source.latitude,
                    source.longitude
            );

            SET @updated_rows = @@ROWCOUNT;


            INSERT INTO [befordring].[Adresse]
            (
                adresse_id,
                adresse_tekst,
                latitude,
                longitude
            )
            SELECT
                source.adresse_id,
                source.adresse_tekst,
                source.latitude,
                source.longitude
            FROM #SourceDeduplicated source
            WHERE NOT EXISTS
            (
                SELECT 1
                FROM [befordring].[Adresse] target
                WHERE target.adresse_id = source.adresse_id
            );

            SET @inserted_rows = @@ROWCOUNT;


            IF @clear_stage_afterwards = 1
            BEGIN
                DELETE FROM [befordring].[Adresse_STG]
                WHERE load_id = @load_id;
            END;

        COMMIT TRANSACTION;

        SELECT
            @staged_rows AS staged_rows,
            @updated_rows AS updated_rows,
            @inserted_rows AS inserted_rows,
            @orphans_swept AS orphan_rows_swept;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH;
END;
GO
/****** Object:  StoredProcedure [befordring].[usp_upsert_elev_from_stg]    Script Date: 14/10/2026 12:53:45 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/*
    Merge the nightly student load from Elev_STG into Elev.

    Elev_STG is filled by the data worker's job, which runs before the RPA.
    That job is the authority on the columns it carries, so a NULL arriving in
    STG is a real change and overwrites — except for the columns listed under
    "Not copied" below.

    Unlike Adresse_STG there is no load_id on this table: the loading job
    truncates and refills it. This procedure therefore processes whatever it
    finds, and does NOT clear the stage afterwards — that table belongs to the
    other job and deleting from it could race their load.

    Not copied, and why:

      adresse_id            Always NULL in STG. Resolved separately from
                            LOIS.CPR.PersonGeoView — see
                            usp_upsert_adresse_ids_from_stg.

      matrikel_id           ALWAYS NULL in STG — the data worker's source has
      ungdomsuddannelse_id  no school. Both are derived from the student's
                            bevillinger instead; see
                            usp_sync_elev_matrikel_from_bevilling, which runs
                            straight after this procedure. Copying either from
                            STG would fight that derivation.

                            This procedure does CLEAR them — see below.

      skoleafstand          Written by the walking-distance step at the end of
                            the nightly run. Copying a stale value from STG
                            would overwrite last night's calculation. This
                            procedure does CLEAR it when the skolekode changes
                            — see below.

      kraever_genberegning  Set by THIS procedure when a watched column
                            changes. Copying it from STG would clobber the flag
                            we just raised, or raise one nothing asked for.

    When skolekode changes, matrikel_id, ungdomsuddannelse_id and skoleafstand
    are cleared and kraever_genberegning is raised.

    Clearing matters because those two are derived from a bevilling, and a
    bevilling that has not caught up with the child's new school now points at
    the wrong one. usp_sync_elev_matrikel_from_bevilling runs next and puts
    back whatever the student's bevilling actually says — but where the student
    has no bevilling to derive from, there is nothing to put back, and the
    stale school must not survive. Leaving it would measure the walking
    distance to a school the child no longer attends.

    The other two kraever_genberegning triggers are raised by the procedures
    that own those columns: usp_sync_elev_matrikel_from_bevilling for
    matrikel_id, usp_upsert_adresse_ids_from_stg for adresse_id. Each flag is
    raised where the change is visible, so none can overwrite another's work.

    All or nothing: one transaction, so a failure part-way leaves Elev exactly
    as it was rather than half-merged.
*/

CREATE   PROCEDURE [befordring].[usp_upsert_elev_from_stg]
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @staged_rows    INT = 0;
    DECLARE @duplicate_cpr  INT = 0;
    DECLARE @updated_rows   INT = 0;
    DECLARE @inserted_rows  INT = 0;
    DECLARE @flagged_rows   INT = 0;

    BEGIN TRY
        BEGIN TRANSACTION;

            /* One row per cpr. There is no load_id or identity column to order
               by, so a duplicate cpr in the stage is resolved arbitrarily —
               and counted, so it shows up in the log rather than silently
               picking a winner every night. Rows without a cpr are dropped:
               the column is nullable in the stage but is the match key here. */
            ;WITH SourceRows AS
            (
                SELECT
                    *,
                    ROW_NUMBER() OVER (
                        PARTITION BY LTRIM(RTRIM(cpr))
                        ORDER BY     (SELECT NULL)
                    ) AS rn
                FROM [befordring].[Elev_STG]
                WHERE NULLIF(LTRIM(RTRIM(cpr)), '') IS NOT NULL
            )
            SELECT
                LTRIM(RTRIM(cpr))         AS cpr,
                adresselinjesnavn,
                navne_adresse_beskyttelse,
                klasseart,
                elevklassetrin,
                klassebetegnelse,
                institution,
                bopaelsdistrikt,
                skolekode
            INTO #Source
            FROM SourceRows
            WHERE rn = 1;

            CREATE UNIQUE CLUSTERED INDEX IX_Source_cpr ON #Source (cpr);

            SELECT @staged_rows = COUNT(*) FROM #Source;

            SELECT @duplicate_cpr =
                (SELECT COUNT(*) FROM [befordring].[Elev_STG]
                 WHERE NULLIF(LTRIM(RTRIM(cpr)), '') IS NOT NULL)
                - @staged_rows;

            /* Which students are about to have their registered school code
               change. Captured before the UPDATE, because afterwards the old
               value is gone. */
            SELECT s.cpr
            INTO   #NeedsRecalc
            FROM   #Source s
            JOIN   [befordring].[Elev] e ON e.cpr = s.cpr
            WHERE  EXISTS (
                       SELECT e.skolekode
                       EXCEPT
                       SELECT s.skolekode
                   );

            SELECT @flagged_rows = COUNT(*) FROM #NeedsRecalc;

            /* EXCEPT compares NULL to NULL as equal, which "<>" does not — so
               a row whose values are unchanged is not rewritten just because
               one of them is NULL. */
            UPDATE target
            SET
                target.adresseringsnavn          = source.adresselinjesnavn,
                target.navne_adresse_beskyttelse = source.navne_adresse_beskyttelse,
                target.klasseart                 = source.klasseart,
                target.elevklassetrin            = source.elevklassetrin,
                target.klassebetegnelse          = source.klassebetegnelse,
                target.institution               = source.institution,
                target.bopaelsdistrikt           = source.bopaelsdistrikt,
                target.skolekode                 = source.skolekode
            FROM [befordring].[Elev] target
            JOIN #Source source ON source.cpr = target.cpr
            WHERE EXISTS
            (
                SELECT
                    target.adresseringsnavn,
                    target.navne_adresse_beskyttelse,
                    target.klasseart,
                    target.elevklassetrin,
                    target.klassebetegnelse,
                    target.institution,
                    target.bopaelsdistrikt,
                    target.skolekode

                EXCEPT

                SELECT
                    source.adresselinjesnavn,
                    source.navne_adresse_beskyttelse,
                    source.klasseart,
                    source.elevklassetrin,
                    source.klassebetegnelse,
                    source.institution,
                    source.bopaelsdistrikt,
                    source.skolekode
            );

            SET @updated_rows = @@ROWCOUNT;

            /* Separate from the UPDATE above so the flag survives a row that
               changed school but nothing else, and is not raised for a row
               where only the name changed.

               matrikel_id and ungdomsuddannelse_id are cleared rather than
               left: the child has just moved school, so whatever supplied them
               before now points at the wrong one. The sync procedure that runs
               next re-derives them where a bevilling exists; where none does,
               cleared is correct.

               skoleafstand is cleared with them, and that is not optional. The
               distance step only recalculates a student whose school has
               coordinates, so a student left WITHOUT a school is skipped — and
               would otherwise keep showing last term's distance, measured to a
               school the child has left, with kraever_genberegning stuck at 1
               and nothing able to clear it.

               It never used to matter: a student with no bevilling had no
               distance to go stale. genberegn_skole can now resolve one from
               an unambiguous skolekode alone, so they can, and this is what
               stops that value outliving the school it was measured to. */
            UPDATE e
            SET    e.kraever_genberegning = 1,
                   e.matrikel_id          = NULL,
                   e.ungdomsuddannelse_id = NULL,
                   e.skoleafstand         = NULL
            FROM   [befordring].[Elev] e
            JOIN   #NeedsRecalc n ON n.cpr = e.cpr;

            /* New students. adresse_id, matrikel_id and ungdomsuddannelse_id
               are left NULL for the procedures that own them, and
               kraever_genberegning starts at 1 because a student with no
               skoleafstand needs one calculated. */
            INSERT INTO [befordring].[Elev]
            (
                cpr,
                adresseringsnavn,
                navne_adresse_beskyttelse,
                klasseart,
                elevklassetrin,
                klassebetegnelse,
                institution,
                bopaelsdistrikt,
                skolekode,
                kraever_genberegning
            )
            SELECT
                source.cpr,
                source.adresselinjesnavn,
                source.navne_adresse_beskyttelse,
                source.klasseart,
                source.elevklassetrin,
                source.klassebetegnelse,
                source.institution,
                source.bopaelsdistrikt,
                source.skolekode,
                1
            FROM #Source source
            WHERE NOT EXISTS
            (
                SELECT 1 FROM [befordring].[Elev] target
                WHERE target.cpr = source.cpr
            );

            SET @inserted_rows = @@ROWCOUNT;

        COMMIT TRANSACTION;

        SELECT
            @staged_rows   AS staged_rows,
            @duplicate_cpr AS duplicate_cpr_dropped,
            @updated_rows  AS updated_rows,
            @inserted_rows AS inserted_rows,
            @flagged_rows  AS skolekode_changed_school_cleared;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH;
END;
GO
/****** Object:  StoredProcedure [befordring].[usp_upsert_foraelder_from_stg]    Script Date: 14/10/2026 12:53:45 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/*
    Merge the nightly guardian load from Foraelder_STG into Foraelder.

    Same contract as usp_upsert_elev_from_stg: the data worker's job owns the
    stage and is the authority on the columns it carries, so a NULL arriving in
    STG overwrites. No load_id on the table, so the stage is processed whole
    and NOT cleared afterwards — it belongs to the other job.

    Matched on the composite key (cpr_foraelder, cpr_elev): a guardian appears
    once per child, so the same adult can legitimately have several rows.

    Not copied, and why:

      adresse_id              Always NULL in STG. Resolved separately from
                              LOIS.CPR.PersonGeoView — see
                              usp_upsert_adresse_ids_from_stg.

      maa_vide_barns_adresse  Deliberately left alone for now. The column is
                              present in the stage, so this is an exclusion
                              rather than an oversight — remove it from this
                              list when the import should own it.

    Guardians whose child is not in Elev are skipped rather than failing the
    batch. FK_Foraelder_Elev would reject them, and the two loads can
    legitimately arrive out of step; the count is returned so a persistent
    mismatch is visible instead of silent.
*/

CREATE   PROCEDURE [befordring].[usp_upsert_foraelder_from_stg]
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @staged_rows     INT = 0;
    DECLARE @duplicate_keys  INT = 0;
    DECLARE @skipped_no_elev INT = 0;
    DECLARE @updated_rows    INT = 0;
    DECLARE @inserted_rows   INT = 0;

    BEGIN TRY
        BEGIN TRANSACTION;

            /* One row per (cpr_foraelder, cpr_elev). No load_id or identity to
               order by, so a duplicate key is resolved arbitrarily and
               counted. Rows missing either half of the key are dropped. */
            ;WITH SourceRows AS
            (
                SELECT
                    *,
                    ROW_NUMBER() OVER (
                        PARTITION BY LTRIM(RTRIM(cpr_foraelder)), LTRIM(RTRIM(cpr_elev))
                        ORDER BY     (SELECT NULL)
                    ) AS rn
                FROM [befordring].[Foraelder_STG]
                WHERE NULLIF(LTRIM(RTRIM(cpr_foraelder)), '') IS NOT NULL
                AND   NULLIF(LTRIM(RTRIM(cpr_elev)), '')      IS NOT NULL
            )
            SELECT
                LTRIM(RTRIM(cpr_foraelder)) AS cpr_foraelder,
                LTRIM(RTRIM(cpr_elev))      AS cpr_elev,
                adresseringsnavn,
                navne_adresse_beskyttelse,
                relation
            INTO #Source
            FROM SourceRows
            WHERE rn = 1;

            SELECT @staged_rows = COUNT(*) FROM #Source;

            SELECT @duplicate_keys =
                (SELECT COUNT(*) FROM [befordring].[Foraelder_STG]
                 WHERE NULLIF(LTRIM(RTRIM(cpr_foraelder)), '') IS NOT NULL
                 AND   NULLIF(LTRIM(RTRIM(cpr_elev)), '')      IS NOT NULL)
                - @staged_rows;

            /* Drop guardians whose child we do not have. Counted first so the
               number is reported rather than inferred from a row difference. */
            SELECT @skipped_no_elev = COUNT(*)
            FROM   #Source s
            WHERE  NOT EXISTS (SELECT 1 FROM [befordring].[Elev] e
                               WHERE e.cpr = s.cpr_elev);

            DELETE s
            FROM   #Source s
            WHERE  NOT EXISTS (SELECT 1 FROM [befordring].[Elev] e
                               WHERE e.cpr = s.cpr_elev);

            CREATE UNIQUE CLUSTERED INDEX IX_Source_key
            ON #Source (cpr_foraelder, cpr_elev);

            /* EXCEPT rather than "<>": it treats NULL as equal to NULL, so an
               unchanged row is not rewritten just because a value is NULL. */
            UPDATE target
            SET
                target.adresseringsnavn          = source.adresseringsnavn,
                target.navne_adresse_beskyttelse = source.navne_adresse_beskyttelse,
                target.relation                  = source.relation
            FROM [befordring].[Foraelder] target
            JOIN #Source source
                ON  source.cpr_foraelder = target.cpr_foraelder
                AND source.cpr_elev      = target.cpr_elev
            WHERE EXISTS
            (
                SELECT
                    target.adresseringsnavn,
                    target.navne_adresse_beskyttelse,
                    target.relation

                EXCEPT

                SELECT
                    source.adresseringsnavn,
                    source.navne_adresse_beskyttelse,
                    source.relation
            );

            SET @updated_rows = @@ROWCOUNT;

            INSERT INTO [befordring].[Foraelder]
            (
                cpr_foraelder,
                cpr_elev,
                adresseringsnavn,
                navne_adresse_beskyttelse,
                relation
            )
            SELECT
                source.cpr_foraelder,
                source.cpr_elev,
                source.adresseringsnavn,
                source.navne_adresse_beskyttelse,
                source.relation
            FROM #Source source
            WHERE NOT EXISTS
            (
                SELECT 1
                FROM   [befordring].[Foraelder] target
                WHERE  target.cpr_foraelder = source.cpr_foraelder
                AND    target.cpr_elev      = source.cpr_elev
            );

            SET @inserted_rows = @@ROWCOUNT;

        COMMIT TRANSACTION;

        SELECT
            @staged_rows     AS staged_rows,
            @duplicate_keys  AS duplicate_keys_dropped,
            @skipped_no_elev AS skipped_child_not_in_elev,
            @updated_rows    AS updated_rows,
            @inserted_rows   AS inserted_rows;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH;
END;
GO
