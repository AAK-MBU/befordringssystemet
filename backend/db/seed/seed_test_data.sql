/* ============================================================
   Test-data reset + seed for the befordring dev database.

   NOTE: Revurdering is a FLAG on Bevilling (revurdering bit), not a
   status. The reassessment test cases (Rikke, Rasmus, Thomas) are
   seeded as Aktiv bevillinger with revurdering = 1 (see the UPDATE
   after the Bevilling inserts). Requires migrations 0005–014 applied.

   Runs inside a transaction that ROLLBACKs by default — change the
   final ROLLBACK to COMMIT once the previewed data looks correct.
   ============================================================ */

USE [Befordringssystemet];

SET XACT_ABORT ON;


/* ------------------------------------------------------------
   SERVERSPÆRRE — udfyld @tilladte_servere før scriptet bruges

   USE [Befordringssystemet] siger INTET om hvilken server man står på:
   databasen hedder det samme på dev og på prod. Uden denne spærre er den
   eneste beskyttelse ROLLBACK'et nederst — og hele pointen med filen er, at
   man laver det om til COMMIT. Et vindue, der stod på prod, sletter så hver
   eneste Koersel, Bevilling, Brev og Elev.

   Fejler LUKKET: listen er tom, så scriptet stopper alle steder, indtil
   servernavnet er skrevet ind. Det er med vilje. En tom liste, der tillod
   alt, ville være værre end ingen spærre, fordi den ville se ud som om der
   var styr på det.

   Find navnet med:   SELECT @@SERVERNAME;
------------------------------------------------------------ */

DECLARE @tilladte_servere TABLE (servernavn SYSNAME);

INSERT INTO @tilladte_servere (servernavn) VALUES
    -- ('MIN-DEV-SERVER'),
    ('srvsql58');

IF NOT EXISTS (SELECT 1 FROM @tilladte_servere WHERE servernavn = @@SERVERNAME)
BEGIN
    RAISERROR(
        'STOPPET: seed_test_data sletter ALLE data og maa ikke koere paa %s. Tilfoej servernavnet til @tilladte_servere, hvis det er en testserver.',
        16, 1, @@SERVERNAME
    );
    RETURN;
END;

PRINT CONCAT('Serverspaerre OK: ', @@SERVERNAME);


BEGIN TRANSACTION;


DELETE FROM [befordring].[Koersel_KoerselstypeTillaeg_LINK];
DELETE FROM [befordring].[Koersel_Ugedag_LINK];
DELETE FROM [befordring].[Bevilling_Hjaelpemiddel_LINK];

-- Brev (migration 014) has an FK to Bevilling, so it has to clear first.
-- Guarded rather than assumed, so the seed still runs against a database where
-- 014 has not been applied yet.
IF OBJECT_ID('[befordring].[Brev]', 'U') IS NOT NULL
    DELETE FROM [befordring].[Brev];

DELETE FROM [befordring].[Koersel];

DELETE FROM [befordring].[Bevilling];

DELETE FROM [befordring].[Foraelder];
DELETE FROM [befordring].[Part];
DELETE FROM [befordring].[Elev];

DELETE FROM [befordring].[Afgoerelsesbrev];
DELETE FROM [befordring].[Befordringstype];
DELETE FROM [befordring].[Hjaelpemiddel];
DELETE FROM [befordring].[Hjemmel];
DELETE FROM [befordring].[KoerselstypeTillaeg];
DELETE FROM [befordring].[PPR_Sagsbehandler];
DELETE FROM [befordring].[Rutetype];
DELETE FROM [befordring].[PortalAuditLog];
DELETE FROM [befordring].[Sagsbehandler];
DELETE FROM [befordring].[Sagsaktivitet];
-- Out of alphabetical order deliberately: Sagsaktivitet holds
-- FK_Sagsaktivitet_Type into this table, so it cannot be cleared until the
-- line above has run.
DELETE FROM [befordring].[SagsaktivitetType];
DELETE FROM [befordring].[Skolematrikel];
DELETE FROM [befordring].[Status];
DELETE FROM [befordring].[Tidspunkt];
DELETE FROM [befordring].[Ugedag];
DELETE FROM [befordring].[Ungdomsuddannelse];



DBCC CHECKIDENT ('[befordring].[Koersel]', RESEED, 0);
DBCC CHECKIDENT ('[befordring].[Bevilling]', RESEED, 0);

DBCC CHECKIDENT ('[befordring].[Afgoerelsesbrev]', RESEED, 0);
DBCC CHECKIDENT ('[befordring].[Befordringstype]', RESEED, 0);
DBCC CHECKIDENT ('[befordring].[Hjaelpemiddel]', RESEED, 0);
DBCC CHECKIDENT ('[befordring].[Hjemmel]', RESEED, 0);
DBCC CHECKIDENT ('[befordring].[KoerselstypeTillaeg]', RESEED, 0);
DBCC CHECKIDENT ('[befordring].[PPR_Sagsbehandler]', RESEED, 0);
DBCC CHECKIDENT ('[befordring].[Sagsbehandler]', RESEED, 0);
DBCC CHECKIDENT ('[befordring].[Sagsaktivitet]', RESEED, 0);
DBCC CHECKIDENT ('[befordring].[Skolematrikel]', RESEED, 0);
DBCC CHECKIDENT ('[befordring].[Status]', RESEED, 0);
DBCC CHECKIDENT ('[befordring].[Tidspunkt]', RESEED, 0);
DBCC CHECKIDENT ('[befordring].[Ugedag]', RESEED, 0);
DBCC CHECKIDENT ('[befordring].[Ungdomsuddannelse]', RESEED, 0);
DBCC CHECKIDENT ('[befordring].[Rutetype]', RESEED, 0);
DBCC CHECKIDENT ('[befordring].[SagsaktivitetType]', RESEED, 0);


PRINT 'Starting test data insert';
PRINT '';

/* ============================================================
   Lookup tables
============================================================ */

INSERT INTO [befordring].[Status]
    (status_tekst, beskrivelse, aktiv)
VALUES
    ('Ny',          'Ny ansøgning',                  1),
    ('Påbegyndt',   'Påbegyndt',                     1),
    ('Afslag',      'Afslag',                        1),
    ('Aktiv',       'Aktiv bevilling eller koersel',  1),
    ('Kommende',    'Kommende',                      1),
    ('Udløbet',     'Udløbet',                       1),
    ('Fejlet',      'Fejlet',                        1),
    ('Ophørt',      'Ophørt',                        1);


-- email kobler rækken til den indloggede bruger: Min side matcher OIDC-
-- claimet mod denne kolonne. Se migration 035.
--
-- Daniel står i BEGGE tabeller med samme adresse, og det er med vilje — det
-- er den eneste måde at se, hvad siden gør, når den samme person er både
-- sagsbehandler og PPR-ansvarlig. Forespørgslen svarer da 'begge' i
-- user_rolle, og rollevælgeren på siden får noget at vælge imellem.
INSERT INTO [befordring].[Sagsbehandler]
    (sagsbehandler_tekst, beskrivelse, aktiv, email)
VALUES
    ('Sofie',  '', 1, N'sofie@aarhus.dk'),
    ('Nina',   '', 1, N'nina@aarhus.dk'),
    ('Daniel', '', 1, N'dadj@aarhus.dk');


INSERT INTO [befordring].[PPR_Sagsbehandler]
    (ppr_sagsbehandler_tekst, beskrivelse, aktiv, email)
VALUES
    ('Hans',    '', 1, N'hans@aarhus.dk'),
    ('Kirsten', '', 1, N'kirsten@aarhus.dk'),
    ('Daniel',  '', 1, N'dadj@aarhus.dk');


-- The event kinds the Sagsforløb feed knows. Created by migration 023
-- (plus 024 and 025); seeded here too so a dev database rebuilt from this
-- file ends up with the same set.
INSERT INTO [befordring].[SagsaktivitetType] (type_kode)
VALUES
    (N'bevilling_oprettet'),
    (N'bevilling_ophoert'),
    (N'bevilling_slettet'),
    (N'brev_afsendt'),
    (N'brev_oprettet'),
    (N'br_revurderet'),
    (N'br_revurderet_fjernet'),
    (N'kommentar'),
    (N'koerselsraekke_oprettet'),
    (N'koerselsraekke_slettet'),
    (N'ppr_ansvarlig_opdateret'),
    (N'ppr_revurderet'),
    (N'ppr_revurderet_fjernet'),
    (N'sagsbehandler_opdateret'),
    (N'status_opdateret');


INSERT INTO [befordring].[Skolematrikel]
    (matrikel_navn, matrikel_adresse, skolekode, er_matrikel_hovedadresse, latitude, longitude)
VALUES
    ('Bakkegårdsskolen',                    'Bjørnshøjvej 1, 8380 Trige',                      751002, 1, 56.253285, 10.149081),
    ('Bavnehøj Skole',                      'Koltvej 19, 21, 8361 Hasselager',                 751016, 1, 56.106589, 10.095978),
    ('Beder Skole',                         'Skoleparken 6, 8330 Beder',                       751004, 1, 56.061574, 10.211609),
    ('Elev Skole',                          'Høvej 10, 8520 Lystrup',                          751006, 1, 56.241190, 10.199622),
    ('Ellevangskolen',                      'Jellebakken 17, 8240 Risskov',                    751003, 1, 56.202644, 10.218707),
    ('Elsted Skole',                        'Elsted Skolevej 6, 8520 Lystrup',                 751007, 1, 56.241526, 10.228948),
    ('Engdalskolen',                        'Hovedgaden 5, 8220 Brabrand',                     751008, 1, 56.152602, 10.109452),
    ('Frederiksbjerg skole',                'Ingerslevs Boulevard 2, 8000 Aarhus C',           751027, 1, 56.145005, 10.197084),
    ('Gammelgaardsskolen',                  'Carit Etlars Vej 31, 8230 Åbyhøj',                751013, 1, 56.159329, 10.157079),
    ('Hasle Skole',                         'Herredsvej 15, 8210 Aarhus V',                    751015, 1, 56.169300, 10.163680),
    ('Holme Skole',                         'Mølleskovvej 11, 8270 Højbjerg',                  751017, 1, 56.116237, 10.178254),
    ('Højvangskolen',                       'Klokkeskovvej 1, 8260 Viby J',                    751018, 1, 56.129903, 10.115003),
    ('Hårup Skole',                         'Salonikivej 14, 8530 Hjortshøj',                  751046, 1, 56.288342, 10.216692),
    ('Kaløvigskolen (Bredevej)',            'Bredevej 2D, 8250 Egå',                           751020, 0, 56.229193, 10.295141),
    ('Kaløvigskolen (Sanatorievej)',        'Sanatorievej 38, 8541 Skødstrup',                 751020, 1, 56.260172, 10.342974),
    ('Kaløvigskolen (Skovager)',            'Skovager 4, 8530 Hjortshøj',                      751020, 0, 56.245661, 10.273222),
    ('Katrinebjergskolen',                  'Katrinebjergvej 60, 8200 Aarhus N',               751019, 1, 56.173827, 10.196322),
    ('Kløverskolen',                        'Karen Blixens Boulevard 59, 8220 Brabrand',       281401, 1, 56.153100, 10.105700),
    ('Kragelundskolen',                     'Aage Jedichs Vej 3, 8270 Højbjerg',               751021, 1, 56.114507, 10.200129),
    ('Langagerskolen (Bøgeskov Høvej)',     'Bøgeskov Høvej 10, 8260 Viby J',                  751090, 1, 56.118367, 10.133548),
    ('Langagerskolen (Kolt Østervej)',      'Kolt Østervej 45, 8361 Hasselager',               751090, 0, 56.109433, 10.075118),
    ('Lisbjergskolen',                      'Jørgen Clevins Gade 31, 8200 Aarhus N',           751022, 1, 56.218634, 10.157948),
    ('Lystrup Skole',                       'Lystrupvej 256, 8520 Lystrup',                    751066, 1, 56.237290, 10.229867),
    ('Læssøesgades Skole',                  'Læssøesgade 24, 8000 Aarhus C',                   751023, 1, 56.146377, 10.188354),
    ('Malling Skole',                       'Lundshøjgårdsvej 19, 8340 Malling',               751024, 1, 56.039315, 10.198617),
    ('Møllevangskolen',                     'Møllevangs Allé 20, 8210 Aarhus V',               751025, 1, 56.164825, 10.184485),
    ('Mårslet Skole',                       'Testrupvej 4, 8320 Mårslet',                      751026, 1, 56.068830, 10.155902),
    ('Netværksskolen',                      'Randersvej 302, 8200 Aarhus N',                   751221, 1, 56.213263, 10.171948),
    ('Næshøjskolen',                        'Gammel Stillingvej 424, 8462 Harlev J',           751055, 1, 56.145839,  9.999646),
    ('Risskov Skole',                       'Vestre Strandallé 97, 8240 Risskov',              751032, 1, 56.192986, 10.229468),
    ('Rosenvangskolen',                     'Rosenvangs Allé 49, 8260 Viby J',                 751033, 1, 56.131271, 10.183323),
    ('Rundhøjskolen',                       'Holmevej 200, 8270 Højbjerg',                     751034, 1, 56.118412, 10.178171),
    ('Sabro-Korsvejskolen',                 'Sabro Skolevej 4, 8471 Sabro',                    751035, 1, 56.211678, 10.025800),
    ('Samsøgades Skole',                    'Ny Munkegade 17, 8000 Aarhus C',                  751036, 1, 56.162449, 10.202540),
    ('Skjoldhøjskolen',                     'Skjoldhøjvej 11, 8381 Tilst',                     751065, 1, 56.174108, 10.113792),
    ('Skovvangskolen',                      'Skovvangsvej 150, 8200 Aarhus N',                 751038, 1, 56.175534, 10.208733),
    ('Skæring Skole',                       'Skæring Skolevej 200, 8250 Egå',                  751056, 1, 56.226157, 10.298083),
    ('Skødstrup Skole',                     'Rosenbakken 4, 8541 Skødstrup',                   751039, 1, 56.271534, 10.308426),
    ('Skåde Skole',                         'Mantziusvej 5, 8270 Højbjerg',                    751040, 1, 56.104037, 10.207346),
    ('Solbjergskolen',                      'Kærgårdsvej 4, 8355 Solbjerg',                    751041, 1, 56.042553, 10.084737),
    ('Stensagerskolen (Janesvej)',          'Janesvej 2, 8220 Brabrand',                       751903, 1, 56.166770, 10.137611),
    ('Stensagerskolen (Stensagervej)',      'Stensagervej 11, 8260 Viby J',                    751903, 0, 56.131239, 10.146707),
    ('Strandskolen',                        'Nellikevej 1, 8240 Risskov',                      751042, 1, 56.200330, 10.245746),
    ('Sygehusundervisning',                 'Palle Juul-Jensens Boulevard 175, 8200 Aarhus N', 751107, 1, 56.190967, 10.165825),
    ('Sødalskolen',                         'Louisevej 29, 8220 Brabrand',                     751014, 1, 56.150375, 10.136786),
    ('Sølystskolen',                        'Egå Havvej 5, 8250 Egå',                          751043, 1, 56.212247, 10.281777),
    ('Søndervangskolen',                    'Søndervangs Allé 40, 8260 Viby J',                751044, 1, 56.111261, 10.149489),
    ('Tilst Skole',                         'Tåstumvænget 8, 8381 Tilst',                      751045, 1, 56.189515, 10.113195),
    ('Tranbjergskolen (Grønløkke Allé)',    'Grønløkke Allé 9, 8310 Tranbjerg J',              280458, 1, 56.094176, 10.124531),
    ('Tranbjergskolen (Kirketorvet)',       'Kirketorvet 22, 8310 Tranbjerg J',                280458, 0, 56.090076, 10.140480),
    ('Vestergårdsskolen (Nordbyvej)',       'Nordbyvej 25, 8260 Viby J',                       751050, 1, 56.129377, 10.156499),
    ('Vestergårdsskolen (Stensagervej)',    'Stensagervej 10, 8260 Viby J',                    751050, 0, 56.130530, 10.148991),
    ('Viby Skole',                          'Kirkevej 2, 8260 Viby J',                         751051, 1, 56.127557, 10.164857),
    ('Virupskolen',                         'Virupvej 75, 8530 Hjortshøj',                     751052, 1, 56.243340, 10.271937),
    ('Vorrevangskolen',                     'Vorregårds Allé 109, 8200 Aarhus N',              751053, 1, 56.185948, 10.199095),
    ('Åby Skole',                           'Åbyvej 80, 8230 Åbyhøj',                          751054, 1, 56.150634, 10.164975),
    ('Herskindskolen',                      'Ladingvej 16, 8464 Galten',                       703003, 1, 56.189651,  9.964099),
    ('Laursens Realskole',                  'Hjelmensgade 12, 8000 Aarhus',                    751060, 1, 56.161890, 10.209509),
    ('Hørningskolen',                       'Vester Alle 18, B, 8362 Hørning',                 715005, 1, 56.089100, 10.032100),
    ('Helgenæs Naturefterskole',            'Vængesøvej 3, 8420 Knebel',                       701303, 1, 56.150487, 10.543970),
    ('Parkvejens Skole',                    'Nølevvej 4, 8300 Odder',                          727004, 1, 55.978700, 10.162600),
    ('Stilling Skole',                      'Gramvej 10, 8660 Skanderborg',                    745003, 1, 56.057879,  9.983251),
    ('Elise Smiths Skole',                  'Ny Munkegade 13, 8000 Aarhus',                    751058, 1, 56.160426, 10.203173);


INSERT INTO [befordring].[Ungdomsuddannelse]
    (ungdomsuddannelse_navn, ungdomsuddannelse_adresse, latitude, longitude)
VALUES
    ('Dansk Brand og sikringsteknisk Institut, Aarhus',   'Runetoften 16, 8210 Aarhus V',           56.175306, 10.141596),
    ('Diakonhøjskolen, Social- og Sundhedsudd.',          'Lyseng Allé 15H, 8270 Højbjerg',         56.110066, 10.202479),
    ('Egå Gymnasium',                                     'Mejlbyvej 4, 8250 Egå',                  56.211969, 10.271199),
    ('Erhvervsgrunduddannelsen i Århus',                  'Olof Palmes Allé 39, 8200 Aarhus N',     56.189424, 10.181944),
    ('International Training Academy ApS, Beauty & Style','Søndergade 45, 8000 Aarhus C',           56.153779, 10.206135),
    ('Jordbrugets UddannelsesCenter, Beder',              'Damgårds Allé 5, 8330 Beder',            56.058613, 10.200661),
    ('Jordbrugets UddannelsesCenter, Bredballegård',      'Nymarksvej 65, 8320 Mårslet',            56.050581, 10.167725),
    ('Marselisborg Gymnasium',                            'Birketinget 9B, 8000 Aarhus C',          56.139194, 10.200802),
    ('Risskov Gymnasium',                                 'Tranekærvej 70, 8240 Risskov',           56.194389, 10.209748),
    ('Rudolf Steiner-Skolen i Aarhus',                    'Strandvejen 102, 8000 Aarhus C',         56.135886, 10.207846),
    ('SOSU Østjylland, Aarhus',                           'Hedeager 33, 8200 Aarhus N',             56.193212, 10.178706),
    ('UCplus A/S, Højbjerg',                              'Øster Parkvej 15, 8270 Højbjerg',        56.104056, 10.148375),
    ('UCplus Højbjerg',                                   'Øster Parkvej 15, 8270 Højbjerg',        56.104056, 10.148375),
    ('Viby Gymnasium',                                    'Søndervangs Allé 45, 8260 Viby J',       56.112858, 10.152582),
    ('Århus Akademi',                                     'Gøteborg Allé 2-4, 8200 Aarhus N',       56.183016, 10.195658),
    ('Aarhus Business College, EUX-gymnasiet',            'Sønderhøj 28, 8260 Viby J',              56.119221, 10.157318),
    ('Aarhus Business College, Handelsfagskolen i Skåde', 'Skåde Skovvej 2, 8270 Højbjerg',         56.097051, 10.218747),
    ('Aarhus Business College, HHX-gymnasiet i Risskov',  'Vejlby Centervej 50, 8240 Risskov',      56.194126, 10.204940),
    ('Aarhus Business College, HHX-gymnasiet i Viby',     'Viemosevej 1, 8260 Viby J',              56.129307, 10.153977),
    ('AARHUS GYMNASIUM, Tilst',                           'Kileparken 25, 8381 Tilst',              56.185741, 10.111676),
    ('AARHUS GYMNASIUM, Viby',                            'Hasselager Allé 10, 8260 Viby J',        56.115676, 10.122718),
    ('AARHUS GYMNASIUM, Aarhus C',                        'Dollerupvej 2, 8000 Aarhus C',           56.156053, 10.187526),
    ('Aarhus Katedralskole',                              'Skolegyde 1, 8000 Aarhus C',             56.156620, 10.211963),
    ('Århus Statsgymnasium',                              'Fenrisvej 33, 8210 Aarhus V',            56.161895, 10.171398),
    ('AARHUS TECH, Viby',                                 'Hasselager Allé 2, 8260 Viby J',         56.113751, 10.124950),
    ('AARHUS TECH, Aarhus C',                             'Dollerupvej 4, 8000 Aarhus C',           56.155449, 10.187265),
    ('AARHUS TECH, Aarhus N',                             'Halmstadgade 6, 8200 Aarhus N',          56.184376, 10.191661);


INSERT INTO [befordring].[Hjaelpemiddel]
    (hjaelpemiddel_tekst, beskrivelse, aktiv)
VALUES
    ('Magnetsele',  '', 1),
    ('Selekappe',   '', 1),
    ('Krampeplan',  '', 1),
    ('Kørestol',    '', 1),
    ('Krykker',     '', 1),
    ('Autostol',    '', 1),
    ('El-kørestol', '', 1);


INSERT INTO [befordring].[Hjemmel]
    (hjemmel_tekst, beskrivelse, aktiv)
VALUES
    ('§ 26, stk. 1 afstand',               '', 1),
    ('§ 26, stk. 2 sygdom',                '', 1),
    ('§ 26, stk. 1 og 2',                  '', 1),
    ('§ 33, stk. 3 (ungdomsskolen)',	   '', 1),
    ('§ 36, stk. 3 frit skolevalg',		   '', 1),
    ('§ 36, stk. 4 retten til at forblive','', 1),
    ('§ 9,  stk. 4 UngiAarhus',            '', 1),
    ('§ 10 (brækket ben)',				   '', 1);


INSERT INTO [befordring].[Afgoerelsesbrev]
    (afgoerelsesbrev_tekst, beskrivelse, aktiv)
VALUES
    ('Afslag: § 9, stk. 4 (UngiAarhus)',										 '', 1),
    ('Afslag: § 26, stk. 1, nr. 1 (afstand)',									 '', 1),
    ('Afslag: § 26, stk. 1, nr. 2 (farlig skolevej)',							 '', 1),
    ('Afslag: § 26, stk. 6, § 36, stk. 3 (frit skolevalg)',						 '', 1),
    ('Afslag: § 33, stk. 3 (ungdomsskolen)',									 '', 1),
    ('Bevilling: § 26, stk. 1, nr. 1 (afstand)',								 '', 1),
    ('Bevilling: § 26, stk. 1, nr. 2 (farlig skolevej)',						 '', 1),
    ('Bevilling: § 26, stk. 2 (sygdom)',										 '', 1),
    ('Bevilling: § 26, stk. 2, § 36, stk. 3 (frit skolevalg)',					 '', 1),
    ('Bevilling: § 26, stk. 2, § 36, stk. 4 (retten til at forblive)',			 '', 1),
    ('Påtænkt afslag: § 26, stk. 1, nr. 2 (farlig skolevej)',                    '', 1),
    ('Påtænkt afslag: § 26, stk. 2 (sygdom)',                                    '', 1),
    ('Påtænkt afslag: § 26, stk. 2, § 36, stk. 4 (retten til at forblive)',      '', 1),
    ('Påtænkt bevilling: § 26, stk. 1 (afstand)',                                '', 1),
    ('Påtænkt bevilling: § 26, stk. 2 (sygdom)',                                 '', 1),
    ('Påtænkt ophør: § 26, stk. 2 (sygdom)',                                     '', 1),
    ('Midlertidig kørsel bevilling: § 26, stk. 2 (brækket ben folkeskole)',      '', 1),
    ('Midlertidig kørsel afslag: § 26, stk. 2 (brækket ben folkeskole)',         '', 1),
    ('Midlertidig kørsel bevilling: § 10 (brækket ben ungdomssuddannelse)',      '', 1),
    ('Midlertidig kørsel afslag: § 10 (brækket ben ungdomssuddannelse)',         '', 1);


INSERT INTO [befordring].[KoerselstypeTillaeg]
    (tillaeg_tekst, beskrivelse, aktiv)
VALUES
    ('Fast forsæde',  '', 1),
    ('Co-driver',     '', 1),
    ('Egen ledsager', '', 1),
    ('Fast sæde',     '', 1);


INSERT INTO [befordring].[Befordringstype]
    (befordringstype_tekst, beskrivelse, aktiv)
VALUES
    ('Rutekørsel',                       '', 1),
    ('Skånekørsel',                      '', 1),
    ('Solokørsel',                       '', 1),
    ('Variabel kørsel',                  '', 1),
    ('Skolerejsekort',                   '', 1),
    ('Skolebus',                         '', 1),
    ('Egen befordring',                  '', 1),
    ('Cykelbus',                         '', 1),
    ('Gåbus',                            '', 1);


INSERT INTO [befordring].[Tidspunkt]
    (tidspunkt_tekst, beskrivelse, aktiv)
VALUES
    ('Morgen',                '', 1),
    ('Eftermiddag',           '', 1),
    ('Morgen og eftermiddag', '', 1);


/* De seks rutetyper, med den sorteringsorden Befordring har bedt om.
   De gamle syv ("Til skole", "Til hjem", "Mellem hjem og klub" m.fl.) er
   IKKE med: en frisk testdatabase skal vise systemet, som det ser ud efter
   migrationen, ikke undervejs. Produktion beholder dem, indtil
   sagsbehandlerne har flyttet rækkerne — se
   db/analyse/koerselsraekker_med_gammel_rutetype.sql. */
INSERT INTO [befordring].[Rutetype]
    (rutetype_tekst, beskrivelse, aktiv, sorteringsorden)
VALUES
    ('Mellem hjem og skole',        '', 1, 1),
    ('Mellem skole, klub, og hjem', '', 1, 2),
    ('Fra hjem til skole',          '', 1, 3),
    ('Fra skole til klub',          '', 1, 4),
    ('Fra skole til hjem',          '', 1, 5),
    ('Fra klub til hjem',           '', 1, 6);


INSERT INTO [befordring].[Ugedag]
    (dag_tekst, beskrivelse, aktiv)
VALUES
    ('Mandag',  NULL,            1),
    ('Tirsdag', NULL,            1),
    ('Onsdag',  NULL,            1),
    ('Torsdag', NULL,            1),
    ('Fredag',  NULL,            1),
    ('Alle',    'Alle hverdage', 1);


/* ============================================================
   Save lookup IDs
============================================================ */

-- Status
DECLARE @status_ny          int = (SELECT TOP 1 status_id FROM [befordring].[Status] WHERE status_tekst = 'Ny'          ORDER BY status_id DESC);
DECLARE @status_paabegundt  int = (SELECT TOP 1 status_id FROM [befordring].[Status] WHERE status_tekst = 'Påbegyndt'   ORDER BY status_id DESC);
DECLARE @status_afslag      int = (SELECT TOP 1 status_id FROM [befordring].[Status] WHERE status_tekst = 'Afslag'      ORDER BY status_id DESC);
DECLARE @status_aktiv       int = (SELECT TOP 1 status_id FROM [befordring].[Status] WHERE status_tekst = 'Aktiv'       ORDER BY status_id DESC);
DECLARE @status_kommende    int = (SELECT TOP 1 status_id FROM [befordring].[Status] WHERE status_tekst = 'Kommende'    ORDER BY status_id DESC);
DECLARE @status_udloebet    int = (SELECT TOP 1 status_id FROM [befordring].[Status] WHERE status_tekst = 'Udløbet'     ORDER BY status_id DESC);
DECLARE @status_fejlet      int = (SELECT TOP 1 status_id FROM [befordring].[Status] WHERE status_tekst = 'Fejlet'      ORDER BY status_id DESC);
DECLARE @status_ophoert     int = (SELECT TOP 1 status_id FROM [befordring].[Status] WHERE status_tekst = 'Ophørt'      ORDER BY status_id DESC);

-- Sagsbehandlere
DECLARE @sagsbehandler_1 int = (SELECT TOP 1 sagsbehandler_id FROM [befordring].[Sagsbehandler] WHERE sagsbehandler_tekst = 'Sofie' ORDER BY sagsbehandler_id DESC);
DECLARE @sagsbehandler_2 int = (SELECT TOP 1 sagsbehandler_id FROM [befordring].[Sagsbehandler] WHERE sagsbehandler_tekst = 'Nina'  ORDER BY sagsbehandler_id DESC);

-- PPR
DECLARE @ppr_1 int = (SELECT TOP 1 ppr_sagsbehandler_id FROM [befordring].[PPR_Sagsbehandler] WHERE ppr_sagsbehandler_tekst = 'Hans'    ORDER BY ppr_sagsbehandler_id DESC);
DECLARE @ppr_2 int = (SELECT TOP 1 ppr_sagsbehandler_id FROM [befordring].[PPR_Sagsbehandler] WHERE ppr_sagsbehandler_tekst = 'Kirsten' ORDER BY ppr_sagsbehandler_id DESC);

-- Skolematrikler
DECLARE @matrikel_1  int = (SELECT TOP 1 matrikel_id FROM [befordring].[Skolematrikel] WHERE matrikel_navn = 'Bakkegårdsskolen'              ORDER BY matrikel_id DESC);
DECLARE @matrikel_2  int = (SELECT TOP 1 matrikel_id FROM [befordring].[Skolematrikel] WHERE matrikel_navn = 'Bavnehøj Skole'                ORDER BY matrikel_id DESC);
DECLARE @matrikel_3  int = (SELECT TOP 1 matrikel_id FROM [befordring].[Skolematrikel] WHERE matrikel_navn = 'Stensagerskolen (Janesvej)'    ORDER BY matrikel_id DESC);
DECLARE @matrikel_4  int = (SELECT TOP 1 matrikel_id FROM [befordring].[Skolematrikel] WHERE matrikel_navn = 'Stensagerskolen (Stensagervej)'ORDER BY matrikel_id DESC);
DECLARE @matrikel_5  int = (SELECT TOP 1 matrikel_id FROM [befordring].[Skolematrikel] WHERE matrikel_navn = 'Engdalskolen'                  ORDER BY matrikel_id DESC);
DECLARE @matrikel_6  int = (SELECT TOP 1 matrikel_id FROM [befordring].[Skolematrikel] WHERE matrikel_navn = 'Solbjergskolen'                ORDER BY matrikel_id DESC);
DECLARE @matrikel_7  int = (SELECT TOP 1 matrikel_id FROM [befordring].[Skolematrikel] WHERE matrikel_navn = 'Samsøgades Skole'              ORDER BY matrikel_id DESC);
DECLARE @matrikel_8  int = (SELECT TOP 1 matrikel_id FROM [befordring].[Skolematrikel] WHERE matrikel_navn = 'Frederiksbjerg skole'          ORDER BY matrikel_id DESC);
DECLARE @matrikel_9  int = (SELECT TOP 1 matrikel_id FROM [befordring].[Skolematrikel] WHERE matrikel_navn = 'Risskov Skole'                 ORDER BY matrikel_id DESC);
DECLARE @matrikel_10 int = (SELECT TOP 1 matrikel_id FROM [befordring].[Skolematrikel] WHERE matrikel_navn = 'Skovvangskolen'                ORDER BY matrikel_id DESC);
DECLARE @matrikel_11 int = (SELECT TOP 1 matrikel_id FROM [befordring].[Skolematrikel] WHERE matrikel_navn = 'Gammelgaardsskolen'            ORDER BY matrikel_id DESC);
DECLARE @matrikel_12 int = (SELECT TOP 1 matrikel_id FROM [befordring].[Skolematrikel] WHERE matrikel_navn = 'Højvangskolen'                 ORDER BY matrikel_id DESC);
DECLARE @matrikel_13 int = (SELECT TOP 1 matrikel_id FROM [befordring].[Skolematrikel] WHERE matrikel_navn = 'Holme Skole'                   ORDER BY matrikel_id DESC);

/* ============================================================
   Datoankre
   ------------------------------------------------------------
   Every date below is derived from GETDATE() rather than written
   as a literal.

   The seeded scenarios (Aktiv, Kommende, Udløbet, revurdering,
   genbehandling) are not stored — usp_recalculate_bevilling_status
   computes them by comparing kørselsperioder against today. Fixed
   dates therefore decay: this file was written in May 2026, and by
   September Sofie's "Kommende" bevilling had silently become Aktiv
   because her kørsel start had passed.

   Anchoring to GETDATE() means the scenarios hold whenever the seed
   is run.

   Skoleåret i Danmark løber august–juni. @skoleaar is the calendar
   year the CURRENT school year started in — before August that is
   last year.
============================================================ */
DECLARE @i_dag date = CAST(GETDATE() AS date);
DECLARE @nu    datetime2 = CAST(CAST(GETDATE() AS date) AS datetime2);

DECLARE @skoleaar int =
    CASE WHEN MONTH(@i_dag) >= 8 THEN YEAR(@i_dag) ELSE YEAR(@i_dag) - 1 END;

DECLARE @start_i_aar  date = DATEFROMPARTS(@skoleaar,     8, 10);   -- indeværende skoleår
DECLARE @slut_i_aar   date = DATEFROMPARTS(@skoleaar + 1, 6, 30);
DECLARE @start_sidste date = DATEFROMPARTS(@skoleaar - 1, 8, 10);   -- forrige skoleår
DECLARE @slut_sidste  date = DATEFROMPARTS(@skoleaar,     6, 30);
DECLARE @start_naeste date = DATEFROMPARTS(@skoleaar + 1, 8, 10);   -- næste skoleår
DECLARE @slut_naeste  date = DATEFROMPARTS(@skoleaar + 2, 6, 30);


-- Ungdomsuddannelser
DECLARE @ungdomsuddannelse_1 int = (SELECT TOP 1 ungdomsuddannelse_id FROM [befordring].[Ungdomsuddannelse] WHERE ungdomsuddannelse_navn = 'Egå Gymnasium'                             ORDER BY ungdomsuddannelse_id DESC);
DECLARE @ungdomsuddannelse_2 int = (SELECT TOP 1 ungdomsuddannelse_id FROM [befordring].[Ungdomsuddannelse] WHERE ungdomsuddannelse_navn = 'Diakonhøjskolen, Social- og Sundhedsudd.' ORDER BY ungdomsuddannelse_id DESC);

-- Hjemler
DECLARE @hjemmel_1 int = (SELECT TOP 1 hjemmel_id FROM [befordring].[Hjemmel] WHERE hjemmel_tekst = '§ 26, stk. 1 afstand'               ORDER BY hjemmel_id DESC);
DECLARE @hjemmel_2 int = (SELECT TOP 1 hjemmel_id FROM [befordring].[Hjemmel] WHERE hjemmel_tekst = '§ 26, stk. 2 sygdom'                ORDER BY hjemmel_id DESC);
DECLARE @hjemmel_3 int = (SELECT TOP 1 hjemmel_id FROM [befordring].[Hjemmel] WHERE hjemmel_tekst = '§ 26, stk. 1 og 2'                  ORDER BY hjemmel_id DESC);
DECLARE @hjemmel_4 int = (SELECT TOP 1 hjemmel_id FROM [befordring].[Hjemmel] WHERE hjemmel_tekst = '§ 36, stk. 3 frit skolevalg'        ORDER BY hjemmel_id DESC);
DECLARE @hjemmel_5 int = (SELECT TOP 1 hjemmel_id FROM [befordring].[Hjemmel] WHERE hjemmel_tekst = '§ 36, stk. 4 retten til at forblive'ORDER BY hjemmel_id DESC);
DECLARE @hjemmel_6 int = (SELECT TOP 1 hjemmel_id FROM [befordring].[Hjemmel] WHERE hjemmel_tekst = '§ 9, stk. 4 UngiAarhus'             ORDER BY hjemmel_id DESC);

-- Afgørelsesbreve
DECLARE @afgoerelsesbrev_1  int = (SELECT TOP 1 afgoerelsesbrev_id FROM [befordring].[Afgoerelsesbrev] WHERE afgoerelsesbrev_tekst = 'Afslag: § 9, stk. 4 (UngiAarhus)'                                ORDER BY afgoerelsesbrev_id DESC);
DECLARE @afgoerelsesbrev_2  int = (SELECT TOP 1 afgoerelsesbrev_id FROM [befordring].[Afgoerelsesbrev] WHERE afgoerelsesbrev_tekst = 'Afslag: § 26, stk. 1, nr. 1 (afstand)'                           ORDER BY afgoerelsesbrev_id DESC);
DECLARE @afgoerelsesbrev_3  int = (SELECT TOP 1 afgoerelsesbrev_id FROM [befordring].[Afgoerelsesbrev] WHERE afgoerelsesbrev_tekst = 'Afslag: § 26, stk. 1, nr. 2 (farlig skolevej)'                   ORDER BY afgoerelsesbrev_id DESC);
DECLARE @afgoerelsesbrev_4  int = (SELECT TOP 1 afgoerelsesbrev_id FROM [befordring].[Afgoerelsesbrev] WHERE afgoerelsesbrev_tekst = 'Afslag: § 26, stk. 6, § 36, stk. 3 (frit skolevalg)'            ORDER BY afgoerelsesbrev_id DESC);
DECLARE @afgoerelsesbrev_5  int = (SELECT TOP 1 afgoerelsesbrev_id FROM [befordring].[Afgoerelsesbrev] WHERE afgoerelsesbrev_tekst = 'Afslag: § 33, stk. 3 (ungdomsskolen)'                            ORDER BY afgoerelsesbrev_id DESC);
DECLARE @afgoerelsesbrev_6  int = (SELECT TOP 1 afgoerelsesbrev_id FROM [befordring].[Afgoerelsesbrev] WHERE afgoerelsesbrev_tekst = 'Bevilling: § 26, stk. 1, nr. 1 (afstand)'                        ORDER BY afgoerelsesbrev_id DESC);
DECLARE @afgoerelsesbrev_7  int = (SELECT TOP 1 afgoerelsesbrev_id FROM [befordring].[Afgoerelsesbrev] WHERE afgoerelsesbrev_tekst = 'Bevilling: § 26, stk. 1, nr. 2 (farlig skolevej)'                ORDER BY afgoerelsesbrev_id DESC);
DECLARE @afgoerelsesbrev_8  int = (SELECT TOP 1 afgoerelsesbrev_id FROM [befordring].[Afgoerelsesbrev] WHERE afgoerelsesbrev_tekst = 'Bevilling: § 26, stk. 2 (sygdom)'                                ORDER BY afgoerelsesbrev_id DESC);
DECLARE @afgoerelsesbrev_9  int = (SELECT TOP 1 afgoerelsesbrev_id FROM [befordring].[Afgoerelsesbrev] WHERE afgoerelsesbrev_tekst = 'Bevilling: § 26, stk. 2, § 36, stk. 3 (frit skolevalg)'         ORDER BY afgoerelsesbrev_id DESC);
DECLARE @afgoerelsesbrev_10 int = (SELECT TOP 1 afgoerelsesbrev_id FROM [befordring].[Afgoerelsesbrev] WHERE afgoerelsesbrev_tekst = 'Bevilling: § 26, stk. 2, § 36, stk. 4 (retten til at forblive)' ORDER BY afgoerelsesbrev_id DESC);

-- Hjælpemidler
DECLARE @hjaelpemiddel_koerestol  int = (SELECT TOP 1 hjaelpemiddel_id FROM [befordring].[Hjaelpemiddel] WHERE hjaelpemiddel_tekst = 'Kørestol'   ORDER BY hjaelpemiddel_id DESC);
DECLARE @hjaelpemiddel_krykker    int = (SELECT TOP 1 hjaelpemiddel_id FROM [befordring].[Hjaelpemiddel] WHERE hjaelpemiddel_tekst = 'Krykker'    ORDER BY hjaelpemiddel_id DESC);
DECLARE @hjaelpemiddel_magnetsele int = (SELECT TOP 1 hjaelpemiddel_id FROM [befordring].[Hjaelpemiddel] WHERE hjaelpemiddel_tekst = 'Magnetsele' ORDER BY hjaelpemiddel_id DESC);
DECLARE @hjaelpemiddel_krampeplan int = (SELECT TOP 1 hjaelpemiddel_id FROM [befordring].[Hjaelpemiddel] WHERE hjaelpemiddel_tekst = 'Krampeplan' ORDER BY hjaelpemiddel_id DESC);
DECLARE @hjaelpemiddel_selekappe  int = (SELECT TOP 1 hjaelpemiddel_id FROM [befordring].[Hjaelpemiddel] WHERE hjaelpemiddel_tekst = 'Selekappe'  ORDER BY hjaelpemiddel_id DESC);
DECLARE @hjaelpemiddel_autostol   int = (SELECT TOP 1 hjaelpemiddel_id FROM [befordring].[Hjaelpemiddel] WHERE hjaelpemiddel_tekst = 'Autostol'   ORDER BY hjaelpemiddel_id DESC);
DECLARE @hjaelpemiddel_elkoerestol int = (SELECT TOP 1 hjaelpemiddel_id FROM [befordring].[Hjaelpemiddel] WHERE hjaelpemiddel_tekst = 'El-kørestol' ORDER BY hjaelpemiddel_id DESC);

-- Tidspunkter

-- Befordringstyper
DECLARE @befordringstype_rute      int = (SELECT TOP 1 befordringstype_id FROM [befordring].[Befordringstype] WHERE befordringstype_tekst = 'Rutekørsel'     ORDER BY befordringstype_id DESC);
DECLARE @befordringstype_egen      int = (SELECT TOP 1 befordringstype_id FROM [befordring].[Befordringstype] WHERE befordringstype_tekst = 'Egen befordring'  ORDER BY befordringstype_id DESC);
DECLARE @befordringstype_skaane    int = (SELECT TOP 1 befordringstype_id FROM [befordring].[Befordringstype] WHERE befordringstype_tekst = 'Skånekørsel'     ORDER BY befordringstype_id DESC);
DECLARE @befordringstype_rejsekort int = (SELECT TOP 1 befordringstype_id FROM [befordring].[Befordringstype] WHERE befordringstype_tekst = 'Skolerejsekort'  ORDER BY befordringstype_id DESC);
DECLARE @befordringstype_variabel  int = (SELECT TOP 1 befordringstype_id FROM [befordring].[Befordringstype] WHERE befordringstype_tekst = 'Variabel kørsel' ORDER BY befordringstype_id DESC);

-- Rutetyper
/* Rutetyperne i den rækkefølge, Befordring har bedt om dem sorteret i
   (Rutetype.sorteringsorden 1-6, se migration 032). Tidspunkt er udeledt af
   dem og sættes ikke længere: kun "fra hjem til skole" er morgen, kun
   "mellem hjem og skole" er begge dele, resten er eftermiddag. */
DECLARE @rutetype_hjem_skole       int = (SELECT TOP 1 rutetype_id FROM [befordring].[Rutetype] WHERE rutetype_tekst = 'Mellem hjem og skole'        ORDER BY rutetype_id DESC);
DECLARE @rutetype_skole_klub_hjem  int = (SELECT TOP 1 rutetype_id FROM [befordring].[Rutetype] WHERE rutetype_tekst = 'Mellem skole, klub, og hjem' ORDER BY rutetype_id DESC);
DECLARE @rutetype_fra_hjem_skole   int = (SELECT TOP 1 rutetype_id FROM [befordring].[Rutetype] WHERE rutetype_tekst = 'Fra hjem til skole'           ORDER BY rutetype_id DESC);
DECLARE @rutetype_fra_skole_klub   int = (SELECT TOP 1 rutetype_id FROM [befordring].[Rutetype] WHERE rutetype_tekst = 'Fra skole til klub'           ORDER BY rutetype_id DESC);
DECLARE @rutetype_fra_skole_hjem   int = (SELECT TOP 1 rutetype_id FROM [befordring].[Rutetype] WHERE rutetype_tekst = 'Fra skole til hjem'           ORDER BY rutetype_id DESC);
DECLARE @rutetype_fra_klub_hjem    int = (SELECT TOP 1 rutetype_id FROM [befordring].[Rutetype] WHERE rutetype_tekst = 'Fra klub til hjem'            ORDER BY rutetype_id DESC);

-- Tillaeg
DECLARE @tillaeg_fast_forsaede int = (SELECT TOP 1 tillaeg_id FROM [befordring].[KoerselstypeTillaeg] WHERE tillaeg_tekst = 'Fast forsæde'  ORDER BY tillaeg_id DESC);
DECLARE @tillaeg_co_driver     int = (SELECT TOP 1 tillaeg_id FROM [befordring].[KoerselstypeTillaeg] WHERE tillaeg_tekst = 'Co-driver'     ORDER BY tillaeg_id DESC);
DECLARE @tillaeg_egen_ledsager int = (SELECT TOP 1 tillaeg_id FROM [befordring].[KoerselstypeTillaeg] WHERE tillaeg_tekst = 'Egen ledsager' ORDER BY tillaeg_id DESC);
DECLARE @tillaeg_fast_saede    int = (SELECT TOP 1 tillaeg_id FROM [befordring].[KoerselstypeTillaeg] WHERE tillaeg_tekst = 'Fast sæde'     ORDER BY tillaeg_id DESC);

-- Ugedage
DECLARE @dag_mandag  int = (SELECT TOP 1 dag_id FROM [befordring].[Ugedag] WHERE dag_tekst = 'Mandag'  ORDER BY dag_id DESC);
DECLARE @dag_tirsdag int = (SELECT TOP 1 dag_id FROM [befordring].[Ugedag] WHERE dag_tekst = 'Tirsdag' ORDER BY dag_id DESC);
DECLARE @dag_onsdag  int = (SELECT TOP 1 dag_id FROM [befordring].[Ugedag] WHERE dag_tekst = 'Onsdag'  ORDER BY dag_id DESC);
DECLARE @dag_torsdag int = (SELECT TOP 1 dag_id FROM [befordring].[Ugedag] WHERE dag_tekst = 'Torsdag' ORDER BY dag_id DESC);
DECLARE @dag_fredag  int = (SELECT TOP 1 dag_id FROM [befordring].[Ugedag] WHERE dag_tekst = 'Fredag'  ORDER BY dag_id DESC);
DECLARE @dag_alle    int = (SELECT TOP 1 dag_id FROM [befordring].[Ugedag] WHERE dag_tekst = 'Alle'    ORDER BY dag_id DESC);


/* ============================================================
   Elev  (31 total)
   1  Kasper Søndergaard   — Aktiv
   2  Kristian Holm        — Aktiv
   3  Rikke Nørgaard       — Aktiv (revurdering)  (adressebeskyttelse)
   4  Rasmus Bjerrum       — Aktiv (revurdering)
   5  Janni Højgaard       — Ny
   6  Jakob Friis          — Ny  (ungdomsuddannelse)
   7  Laura Bech           — Påbegyndt
   8  Martin Kjeldsen      — Afslag
   9  Sofie Lund           — Kommende
   10 Peter Møller         — Udløbet
   11 Emma Grønberg        — Fejlet
   12 Anders Dalsgaard     — Ophørt
   13 Mette Christensen    — Aktiv  (ungdomsuddannelse)
   14 Thomas Vestergaard   — Aktiv (revurdering)

   15 Astrid Mikkelsen     — Ny
   16 Oliver Bak           — Ny
   17 Freja Toft           — Ny  (adressebeskyttelse)
   18 Noah Kjær            — Ny  (midlertidig kørsel)
   19 Clara Winther        — Ny
   20 Villads Brandt       — Ny
   21 Alma Storm           — Ny
   22 Elias Munk           — Ny
   23 Ida Sylvest          — Ny  (0. klasse)
   24 Malthe Overgaard     — Ny  (ungdomsuddannelse)
   25 Liva Rask            — Ny
   26 Storm Bendtsen       — Ny

   27 Sofie Entydig        — INGEN bevilling, entydig skolekode
   28 Mads Flertydig       — INGEN bevilling, skolekode med tre matrikler
   29 Emma Ukendt          — INGEN bevilling, ukendt skolekode
   30 Victor Bevaret       — INGEN bevilling, matrikel sat og gyldig
   31 Liva Stale           — INGEN bevilling, matrikel sat men forældet

   27-31 findes udelukkende for at teste udledningen af skole uden bevilling —
   se deres eget afsnit længere nede.

   De fleste "Ny"-bevillinger får desuden OS2Forms-ansøgningsdata. 5 Janni og
   6 Jakob får bevidst ingen — de står for de håndlavede. Se afsnittet
   "OS2Forms-ansøgningsdata" nederst.
============================================================ */

INSERT INTO [befordring].[Elev]
    (cpr, adresseringsnavn, navne_adresse_beskyttelse, adresse_id,
     skoleafstand, klasseart, elevklassetrin, klassebetegnelse,
     institution, bopaelsdistrikt, matrikel_id, ungdomsuddannelse_id, skolekode)
VALUES
(
    '0101101234', 'Kasper Søndergaard', 0, 'A79762E7-52BF-4199-A026-4AB42E1138A7',
    2.8, 'Normalklasse', '1', '1A',
    'SFO - Bakkegårdsskolen', 'Bakkegårdsskolen',
    @matrikel_1, NULL, 751002
),
(
    '0202101234', 'Kristian Holm', 0, '00002732-733C-433A-A5DA-A7D428A980CF',
    4.2, 'Normalklasse', '2', '2B',
    'SFO - Bavnehøj Skole', 'Bavnehøj Skole',
    @matrikel_2, NULL, 751016
),
(
    '0303101234', 'Rikke Nørgaard', 1, '00002EC8-9A05-423C-ABF2-3D0F4CCB03E0',
    2.1, 'Modtageklasse', '3', '3C',
    'SFO - Stensagerskolen', 'Stensagerskolen',
    @matrikel_3, NULL, 751903
),
(
    '0404101234', 'Rasmus Bjerrum', 0, '000059B7-1FE6-4ED2-8386-D9578B2A8859',
    2.9, 'Normalklasse', '4', '4D',
    'SFO - Stensagerskolen', 'Stensagerskolen',
    @matrikel_4, NULL, 751903
),
(
    '0505101234', 'Janni Højgaard', 0, '0000670C-4F89-4C07-B77B-F9B82AF01C80',
    6.8, 'Specialklasse', '5', '5E',
    'SFO - Engdalskolen', 'Engdalskolen',
    @matrikel_5, NULL, 751008
),
(
    '0606101234', 'Jakob Friis', 0, '00009B67-504C-4FE0-B1D1-39126722DF0F',
    6.8, 'Normalklasse', '10', '10A',
    '', '',
    NULL, @ungdomsuddannelse_1, ''
),
-- 7: Laura Bech — Påbegyndt
(
    '0707101234', 'Laura Bech', 0, '00009E24-9877-4F17-8020-04A0B29E704F',
    1.8, 'Normalklasse', '2', '2C',
    'SFO - Samsøgades Skole', 'Samsøgades Skole',
    @matrikel_7, NULL, 751036
),
-- 8: Martin Kjeldsen — Afslag
(
    '0808101234', 'Martin Kjeldsen', 0, '0000BF23-21F1-4FBB-85AE-3089BC6CF623',
    0.9, 'Normalklasse', '3', '3A',
    'SFO - Frederiksbjerg skole', 'Frederiksbjerg skole',
    @matrikel_8, NULL, 751027
),
-- 9: Sofie Lund — Kommende
(
    '0909101234', 'Sofie Lund', 0, '0000C127-AB48-48C7-9770-EDA49D39EB5A',
    5.2, 'Normalklasse', '5', '5B',
    'SFO - Risskov Skole', 'Risskov Skole',
    @matrikel_9, NULL, 751032
),
-- 10: Peter Møller — Udløbet
(
    '1010101234', 'Peter Møller', 0, '0000E92C-BB46-4745-A0AE-90950142AF79',
    3.4, 'Normalklasse', '7', '7D',
    '', 'Skovvangskolen',
    @matrikel_10, NULL, 751038
),
-- 11: Emma Grønberg — Fejlet
(
    '1111101234', 'Emma Grønberg', 0, '0000EE38-A966-4A72-9C34-19B0A32AD367',
    0.6, 'Specialklasse', '1', '1A',
    'SFO - Gammelgaardsskolen', 'Gammelgaardsskolen',
    @matrikel_11, NULL, 751013
),
-- 12: Anders Dalsgaard — Ophørt
(
    '1212101234', 'Anders Dalsgaard', 0, '0000F131-D663-4434-A585-D30CA601B571',
    8.4, 'Normalklasse', '8', '8E',
    '', 'Højvangskolen',
    @matrikel_12, NULL, 751018
),
-- 13: Mette Christensen — Aktiv (ungdomsuddannelse)
(
    '1313101234', 'Mette Christensen', 0, '0000F5F4-9278-43A5-9BA8-24C21D76610C',
    12.1, 'Normalklasse', '10', '10B',
    '', '',
    NULL, @ungdomsuddannelse_2, ''
),
-- 14: Thomas Vestergaard — Aktiv (revurdering)
(
    '1414101234', 'Thomas Vestergaard', 0, '0000AAF0-826F-4458-B26F-4317AD2A4979',
    6.7, 'Normalklasse', '6', '6C',
    'SFO - Holme Skole', 'Holme Skole',
    @matrikel_13, NULL, 751017
);


/* ============================================================
   Elev 15-26 — twelve more students, all with a bevilling at Ny

   Added so "Nye ansøgninger" has a realistic volume to work with.
   Addresses are reused from the fourteen above on purpose: the seed does not
   insert into Adresse, so every adresse_id here has to be one the table
   already holds, and these are known good.
============================================================ */

INSERT INTO [befordring].[Elev]
    (cpr, adresseringsnavn, navne_adresse_beskyttelse, adresse_id,
     skoleafstand, klasseart, elevklassetrin, klassebetegnelse,
     institution, bopaelsdistrikt, matrikel_id, ungdomsuddannelse_id, skolekode)
VALUES
(
    '1515101234', 'Astrid Mikkelsen', 0, '000021C5-E9EE-411D-B2D8-EC9161780CCD',
    10.9, 'Normalklasse', '2', '2A',
    'SFO - Solbjergskolen', 'Solbjergskolen',
    @matrikel_6, NULL, 751041
),
(
    '1616101234', 'Oliver Bak', 0, '00002732-733C-433A-A5DA-A7D428A980CF',
    3.1, 'Normalklasse', '4', '4B',
    'SFO - Samsøgades Skole', 'Samsøgades Skole',
    @matrikel_7, NULL, 751036
),
(
    '1717101234', 'Freja Toft', 1, '00002EC8-9A05-423C-ABF2-3D0F4CCB03E0',
    7.4, 'Specialklasse', '3', '3A',
    'SFO - Frederiksbjerg skole', 'Frederiksbjerg skole',
    @matrikel_8, NULL, 751027
),
(
    '1818101234', 'Noah Kjær', 0, '000059B7-1FE6-4ED2-8386-D9578B2A8859',
    2.4, 'Normalklasse', '1', '1C',
    'SFO - Risskov Skole', 'Risskov Skole',
    @matrikel_9, NULL, 751032
),
(
    '1919101234', 'Clara Winther', 0, '0000670C-4F89-4C07-B77B-F9B82AF01C80',
    8.2, 'Modtageklasse', '5', '5B',
    'SFO - Skovvangskolen', 'Skovvangskolen',
    @matrikel_10, NULL, 751038
),
(
    '2020101234', 'Villads Brandt', 0, '00009B67-504C-4FE0-B1D1-39126722DF0F',
    6.1, 'Normalklasse', '7', '7A',
    '', 'Gammelgaardsskolen',
    @matrikel_11, NULL, 751013
),
(
    '2121101234', 'Alma Storm', 0, '00009E24-9877-4F17-8020-04A0B29E704F',
    4.8, 'Specialklasse', '6', '6B',
    'SFO - Højvangskolen', 'Højvangskolen',
    @matrikel_12, NULL, 751018
),
(
    '2222101234', 'Elias Munk', 0, '0000AAF0-826F-4458-B26F-4317AD2A4979',
    9.6, 'Normalklasse', '8', '8A',
    '', 'Holme Skole',
    @matrikel_13, NULL, 751017
),
(
    '2323101234', 'Ida Sylvest', 0, '0000BF23-21F1-4FBB-85AE-3089BC6CF623',
    2.7, 'Normalklasse', '0', '0A',
    'SFO - Bakkegårdsskolen', 'Bakkegårdsskolen',
    @matrikel_1, NULL, 751002
),
(
    '2424101234', 'Malthe Overgaard', 0, '0000C127-AB48-48C7-9770-EDA49D39EB5A',
    11.3, '', '10', '',
    '', '',
    NULL, @ungdomsuddannelse_2, ''
),
(
    '2525101234', 'Liva Rask', 0, '0000E92C-BB46-4745-A0AE-90950142AF79',
    6.5, 'Normalklasse', '9', '9C',
    '', 'Engdalskolen',
    @matrikel_5, NULL, 751008
),
(
    '2626101234', 'Storm Bendtsen', 0, '0000EE38-A966-4A72-9C34-19B0A32AD367',
    3.9, 'Normalklasse', '3', '3D',
    'SFO - Bavnehøj Skole', 'Bavnehøj Skole',
    @matrikel_2, NULL, 751016
);


/* ============================================================
   Elev 27-31 — skolekode-udledning UDEN bevilling

   Fem elever med INGEN bevilling overhovedet. De findes for at teste
   genberegn_skole-knappen på stamdata og den natlige synkronisering:

     27  Entydig skolekode.      Beder Skole (751004) har præcis én matrikel,
                                 og den har koordinater. Knappen skal sætte
                                 matrikel_id og beregne gåafstand.

     28  Flertydig skolekode.    Kaløvigskolen (751020) har TRE matrikler.
                                 Knappen skal nægte at gætte og sige, at
                                 skolekoden ikke peger på præcis én matrikel.

     29  Ukendt skolekode.       759999 findes ikke i Skolematrikel. Samme
                                 besked som 28 — der er intet at slå op.

     30  Allerede udledt, gyldig. matrikel_id er sat i forvejen og hører til
                                 elevens egen skolekode. usp_sync_elev_matrikel
                                 _from_bevilling må IKKE rydde den, selv om der
                                 ingen bevilling er. Kør proceduren og tjek at
                                 den overlever.

     31  Allerede udledt, STALE. matrikel_id peger på Beder Skole (751004),
                                 men eleven er registreret på Holme Skole
                                 (751017). Den SKAL ryddes af samme procedure.

   kraever_genberegning = 1 på 27-29: sådan ser en ny elev ud. De skal stadig
   IKKE samles op af nattens afstandsberegning, fordi den kræver en skole med
   koordinater — og de har ingen matrikel. Det er den afgrænsning, der gør, at
   de 26.000 elever uden bevilling ikke pludselig står i kø til ORS.

   Adresserne er genbrugt fra eleverne ovenfor, af samme grund som der: seedet
   indsætter ikke i Adresse, så adresse_id skal være en tabellen allerede har.
============================================================ */

DECLARE @matrikel_beder int =
    (SELECT TOP 1 matrikel_id FROM [befordring].[Skolematrikel]
      WHERE skolekode = 751004 ORDER BY matrikel_id);

INSERT INTO [befordring].[Elev]
    (cpr, adresseringsnavn, navne_adresse_beskyttelse, adresse_id,
     skoleafstand, klasseart, elevklassetrin, klassebetegnelse,
     institution, bopaelsdistrikt, matrikel_id, ungdomsuddannelse_id, skolekode,
     kraever_genberegning)
VALUES
-- 27: entydig skolekode, intet udledt endnu -> knappen skal kunne klare den
(
    '2727101234', 'Sofie Entydig', 0, '000021C5-E9EE-411D-B2D8-EC9161780CCD',
    NULL, 'Normalklasse', '3', '3A',
    '', 'Beder Skole',
    NULL, NULL, 751004, 1
),
-- 28: tre matrikler på samme skolekode -> knappen skal nægte at vælge
(
    '2828101234', 'Mads Flertydig', 0, '00002732-733C-433A-A5DA-A7D428A980CF',
    NULL, 'Normalklasse', '5', '5A',
    '', 'Kaløvigskolen',
    NULL, NULL, 751020, 1
),
-- 29: skolekoden findes slet ikke i Skolematrikel
(
    '2929101234', 'Emma Ukendt', 0, '00002EC8-9A05-423C-ABF2-3D0F4CCB03E0',
    NULL, 'Normalklasse', '2', '2A',
    '', '',
    NULL, NULL, 759999, 1
),
-- 30: udledt i forvejen og i overensstemmelse med skolekoden -> skal bevares
(
    '3030101234', 'Victor Bevaret', 0, '000059B7-1FE6-4ED2-8386-D9578B2A8859',
    3.3, 'Normalklasse', '4', '4A',
    '', 'Beder Skole',
    @matrikel_beder, NULL, 751004, 0
),
-- 31: udledt i forvejen, men peger på en anden skole end skolekoden -> ryddes
(
    '3131101234', 'Liva Stale', 0, '0000670C-4F89-4C07-B77B-F9B82AF01C80',
    9.9, 'Normalklasse', '6', '6A',
    '', 'Holme Skole',
    @matrikel_beder, NULL, 751017, 0
);


/* ============================================================
   Foraelder  (14 total — one per elev; 15-26 added further down)
============================================================ */

INSERT INTO [befordring].[Foraelder]
    (cpr_foraelder, cpr_elev, adresseringsnavn, adresse_id,
     navne_adresse_beskyttelse, relation, maa_vide_barns_adresse)
VALUES
('1111111111', '0101101234', 'Jeppe Søndergaard',  'A79762E7-52BF-4199-A026-4AB42E1138A7', 0, 'Mor', 1),
('2222222222', '0202101234', 'Maja Holm',          '00002732-733C-433A-A5DA-A7D428A980CF', 0, 'Mor', 0),
('3333333333', '0303101234', 'Nadia Nørgaard',     '00002EC8-9A05-423C-ABF2-3D0F4CCB03E0', 0, 'Mor', 0),
('4444444444', '0404101234', 'Brian Bjerrum',      '000059B7-1FE6-4ED2-8386-D9578B2A8859', 0, 'Tante', 0),
('5555555555', '0505101234', 'Hanne Højgaard',     '0000670C-4F89-4C07-B77B-F9B82AF01C80', 0, 'Mor', 1),
('6666666666', '0606101234', 'Torben Friis',       '00009B67-504C-4FE0-B1D1-39126722DF0F', 0, 'Far', 0),
('7777777777', '0707101234', 'Lotte Bech',         '00009E24-9877-4F17-8020-04A0B29E704F', 0, 'Far', 1),
('8888888888', '0808101234', 'Kim Kjeldsen',       '0000BF23-21F1-4FBB-85AE-3089BC6CF623', 0, 'Mor', 1),
('9999999999', '0909101234', 'Anni Lund',          '0000C127-AB48-48C7-9770-EDA49D39EB5A', 0, 'Mor', 1),
('1010101010', '1010101234', 'Henrik Møller',      '0000E92C-BB46-4745-A0AE-90950142AF79', 0, 'Mor', 1),
('1111111110', '1111101234', 'Gitte Grønberg',     '0000EE38-A966-4A72-9C34-19B0A32AD367', 0, 'Mor', 0),
('1212121212', '1212101234', 'Søren Dalsgaard',    '0000F131-D663-4434-A585-D30CA601B571', 0, 'Mor', 1),
('1313131313', '1313101234', 'Dorthe Christensen', '0000F5F4-9278-43A5-9BA8-24C21D76610C', 0, 'Mor', 1),
('1414141414', '1414101234', 'Kurt Vestergaard',   '0000AAF0-826F-4458-B26F-4317AD2A4979', 0, 'Mor', 1);


/* ============================================================
   Foraelder 15-26 — one per new student
============================================================ */

INSERT INTO [befordring].[Foraelder]
    (cpr_foraelder, cpr_elev, adresseringsnavn, adresse_id,
     navne_adresse_beskyttelse, relation, maa_vide_barns_adresse)
VALUES
('1515151515', '1515101234', 'Pernille Mikkelsen', '000021C5-E9EE-411D-B2D8-EC9161780CCD', 0, 'Mor', 1),
('1616161616', '1616101234', 'Jonas Bak', '00002732-733C-433A-A5DA-A7D428A980CF', 0, 'Far', 1),
('1717171717', '1717101234', 'Camilla Toft', '00002EC8-9A05-423C-ABF2-3D0F4CCB03E0', 0, 'Mor', 0),
('1818181818', '1818101234', 'Martin Kjær', '000059B7-1FE6-4ED2-8386-D9578B2A8859', 0, 'Far', 1),
('1919191919', '1919101234', 'Sanne Winther', '0000670C-4F89-4C07-B77B-F9B82AF01C80', 0, 'Mor', 1),
('2020202020', '2020101234', 'Ole Brandt', '00009B67-504C-4FE0-B1D1-39126722DF0F', 0, 'Far', 1),
('2121212121', '2121101234', 'Line Storm', '00009E24-9877-4F17-8020-04A0B29E704F', 0, 'Mor', 1),
('2222222220', '2222101234', 'Rikke Munk', '0000AAF0-826F-4458-B26F-4317AD2A4979', 0, 'Mor', 0),
('2323232323', '2323101234', 'Jesper Sylvest', '0000BF23-21F1-4FBB-85AE-3089BC6CF623', 0, 'Far', 1),
('2424242424', '2424101234', 'Bente Overgaard', '0000C127-AB48-48C7-9770-EDA49D39EB5A', 0, 'Mor', 1),
('2525252525', '2525101234', 'Anders Rask', '0000E92C-BB46-4745-A0AE-90950142AF79', 0, 'Far', 1),
('2626262626', '2626101234', 'Mette Bendtsen', '0000EE38-A966-4A72-9C34-19B0A32AD367', 0, 'Mor', 1);


/* ============================================================
   Bevilling
============================================================ */

-- 1: Kasper — Aktiv
INSERT INTO [befordring].[Bevilling]
    (cpr_elev, adresse_id, status_id, matrikel_id, ungdomsuddannelse_id,
     hjemmel_id, afgoerelsesbrev_id, revurderingsdato, befordringsudvalg,
     esdh_noegle, sagsbehandler_id, ppr_sagsbehandler_id,
     ansoegningsdato, sagsbehandlingsdato, relation_til_barnet,
     foerste_koersel_dato, ansoegningstype,
     afstandskriterie_dato, afstandskriterie_klassetrin,
     begrundelse_fra_formular, created_by, updated_by, aktiv)
VALUES
(
    '0101101234', 'A79762E7-52BF-4199-A026-4AB42E1138A7', @status_aktiv, @matrikel_1, NULL,
    @hjemmel_1, @afgoerelsesbrev_6, @slut_i_aar, DATEADD(DAY, -10, @i_dag),
    'ESDH-TEST-001', @sagsbehandler_1, @ppr_1,
    DATEADD(MONTH, -7, @i_dag), NULL, 'Forældremyndighed',
    @start_i_aar, 'Fast kørsel',
    @slut_i_aar, 3,
    'Sygdom', 'test_seed', 'test_seed', 1
);
DECLARE @bevilling_1 int = SCOPE_IDENTITY();


-- 2: Kristian — Aktiv
INSERT INTO [befordring].[Bevilling]
    (cpr_elev, adresse_id, status_id, matrikel_id, ungdomsuddannelse_id,
     hjemmel_id, afgoerelsesbrev_id, revurderingsdato, befordringsudvalg,
     esdh_noegle, sagsbehandler_id, ppr_sagsbehandler_id,
     ansoegningsdato, sagsbehandlingsdato, relation_til_barnet,
     foerste_koersel_dato, ansoegningstype,
     afstandskriterie_dato, afstandskriterie_klassetrin,
     begrundelse_fra_formular, created_by, updated_by, aktiv)
VALUES
(
    '0202101234', '00002732-733C-433A-A5DA-A7D428A980CF', @status_aktiv, @matrikel_2, NULL,
    @hjemmel_2, @afgoerelsesbrev_8, @slut_i_aar, DATEADD(DAY, -10, @i_dag),
    'ESDH-TEST-002', @sagsbehandler_2, @ppr_2,
    DATEADD(MONTH, -6, @i_dag), NULL, 'Forældremyndighed',
    @start_i_aar, 'Fast kørsel',
    @slut_i_aar, 3,
    'Farlig trafikvej', 'test_seed', 'test_seed', 1
);
DECLARE @bevilling_2 int = SCOPE_IDENTITY();


-- 3: Rikke — Aktiv (flagged for revurdering below)
INSERT INTO [befordring].[Bevilling]
    (cpr_elev, adresse_id, status_id, matrikel_id,
     hjemmel_id, afgoerelsesbrev_id, revurderingsdato, befordringsudvalg,
     esdh_noegle, sagsbehandler_id, ppr_sagsbehandler_id,
     ansoegningsdato, sagsbehandlingsdato, relation_til_barnet,
     foerste_koersel_dato, ansoegningstype,
     afstandskriterie_dato, afstandskriterie_klassetrin,
     begrundelse_fra_formular, created_by, updated_by, aktiv)
VALUES
(
    '0303101234', '00002EC8-9A05-423C-ABF2-3D0F4CCB03E0', @status_aktiv, @matrikel_3,
    @hjemmel_3, @afgoerelsesbrev_7, DATEADD(MONTH, 1, @i_dag), DATEADD(DAY, -25, @i_dag),
    'ESDH-TEST-003', @sagsbehandler_1, @ppr_1,
    DATEADD(MONTH, -14, @i_dag), NULL, 'Forældremyndighed',
    @start_sidste, 'Fast kørsel',
    @slut_i_aar, 6,
    'Afstand', 'test_seed', 'test_seed', 1
);
DECLARE @bevilling_3 int = SCOPE_IDENTITY();


-- 4: Rasmus — Aktiv (flagged for revurdering below)
INSERT INTO [befordring].[Bevilling]
    (cpr_elev, adresse_id, status_id, matrikel_id, ungdomsuddannelse_id,
     hjemmel_id, afgoerelsesbrev_id, revurderingsdato, befordringsudvalg,
     esdh_noegle, sagsbehandler_id, ppr_sagsbehandler_id,
     ansoegningsdato, sagsbehandlingsdato, relation_til_barnet,
     foerste_koersel_dato, ansoegningstype,
     afstandskriterie_dato, afstandskriterie_klassetrin,
     begrundelse_fra_formular, created_by, updated_by, aktiv)
VALUES
(
    '0404101234', '000059B7-1FE6-4ED2-8386-D9578B2A8859', @status_aktiv, @matrikel_4, NULL,
    @hjemmel_4, @afgoerelsesbrev_4, DATEADD(DAY, 45, @i_dag), DATEADD(DAY, -40, @i_dag),
    'ESDH-TEST-004', @sagsbehandler_2, @ppr_2,
    DATEADD(MONTH, -9, @i_dag), NULL, 'Værge',
    @start_i_aar, 'Fast kørsel',
    @slut_i_aar, 9,
    'Afstand', 'test_seed', 'test_seed', 1
);
DECLARE @bevilling_4 int = SCOPE_IDENTITY();


-- 5: Janni — Ny
INSERT INTO [befordring].[Bevilling]
    (cpr_elev, adresse_id, status_id, matrikel_id, ungdomsuddannelse_id,
     hjemmel_id, afgoerelsesbrev_id, revurderingsdato, befordringsudvalg,
     esdh_noegle, sagsbehandler_id, ppr_sagsbehandler_id,
     ansoegningsdato, sagsbehandlingsdato, relation_til_barnet,
     foerste_koersel_dato, ansoegningstype,
     afstandskriterie_dato, afstandskriterie_klassetrin,
     begrundelse_fra_formular, created_by, updated_by, aktiv)
VALUES
(
    '0505101234', '0000670C-4F89-4C07-B77B-F9B82AF01C80', @status_ny, @matrikel_5, NULL,
    NULL, NULL, NULL, NULL,
    'ESDH-TEST-005', NULL, NULL,
    DATEADD(DAY, -6, @i_dag), NULL, 'Forældremyndighed',
    DATEADD(DAY, 21, @i_dag), 'Fast kørsel',
    NULL, NULL,
    'Afstand', 'test_seed', 'test_seed', 1
);


-- 6: Jakob — Ny
INSERT INTO [befordring].[Bevilling]
    (cpr_elev, adresse_id, status_id, matrikel_id, ungdomsuddannelse_id,
     hjemmel_id, afgoerelsesbrev_id, revurderingsdato, befordringsudvalg,
     esdh_noegle, sagsbehandler_id, ppr_sagsbehandler_id,
     ansoegningsdato, sagsbehandlingsdato, relation_til_barnet,
     foerste_koersel_dato, ansoegningstype,
     afstandskriterie_dato, afstandskriterie_klassetrin,
     begrundelse_fra_formular, created_by, updated_by, aktiv)
VALUES
(
    '0606101234', '00009B67-504C-4FE0-B1D1-39126722DF0F', @status_ny, NULL, @ungdomsuddannelse_1,
    NULL, NULL, NULL, NULL,
    'ESDH-TEST-006', NULL, NULL,
    DATEADD(DAY, -2, @i_dag), NULL, 'Forældremyndighed',
    DATEADD(DAY, 7, @i_dag), 'Midlertidig kørsel',
    NULL, NULL,
    'Sygdom', 'test_seed', 'test_seed', 1
);


-- 7: Laura — Påbegyndt
INSERT INTO [befordring].[Bevilling]
    (cpr_elev, adresse_id, status_id, matrikel_id, ungdomsuddannelse_id,
     hjemmel_id, afgoerelsesbrev_id, revurderingsdato, befordringsudvalg,
     esdh_noegle, sagsbehandler_id, ppr_sagsbehandler_id,
     ansoegningsdato, sagsbehandlingsdato, relation_til_barnet,
     foerste_koersel_dato, ansoegningstype,
     afstandskriterie_dato, afstandskriterie_klassetrin,
     begrundelse_fra_formular, created_by, updated_by, aktiv)
VALUES
(
    '0707101234', '00009E24-9877-4F17-8020-04A0B29E704F', @status_paabegundt, @matrikel_7, NULL,
    @hjemmel_1, NULL, @slut_i_aar, NULL,
    'ESDH-TEST-007', @sagsbehandler_1, @ppr_1,
    DATEADD(DAY, -24, @i_dag), NULL, 'Mor',
    DATEADD(DAY, 14, @i_dag), 'Fast kørsel',
    @slut_i_aar, 10,
    'Afstand', 'test_seed', 'test_seed', 1
);


-- 8: Martin — Afslag
INSERT INTO [befordring].[Bevilling]
    (cpr_elev, adresse_id, status_id, matrikel_id, ungdomsuddannelse_id,
     hjemmel_id, afgoerelsesbrev_id, revurderingsdato, befordringsudvalg,
     esdh_noegle, sagsbehandler_id, ppr_sagsbehandler_id,
     ansoegningsdato, sagsbehandlingsdato, relation_til_barnet,
     foerste_koersel_dato, ansoegningstype,
     afstandskriterie_dato, afstandskriterie_klassetrin,
     begrundelse_fra_formular, created_by, updated_by, aktiv)
VALUES
(
    '0808101234', '0000BF23-21F1-4FBB-85AE-3089BC6CF623', @status_afslag, @matrikel_8, NULL,
    @hjemmel_1, @afgoerelsesbrev_2, NULL, NULL,
    'ESDH-TEST-008', @sagsbehandler_2, @ppr_1,
    DATEADD(MONTH, -3, @i_dag), NULL, 'Far',
    NULL, 'Fast kørsel',
    NULL, 6,
    'Afstand', 'test_seed', 'test_seed', 1
);


-- 9: Sofie — Kommende
INSERT INTO [befordring].[Bevilling]
    (cpr_elev, adresse_id, status_id, matrikel_id, ungdomsuddannelse_id,
     hjemmel_id, afgoerelsesbrev_id, revurderingsdato, befordringsudvalg,
     esdh_noegle, sagsbehandler_id, ppr_sagsbehandler_id,
     ansoegningsdato, sagsbehandlingsdato, relation_til_barnet,
     foerste_koersel_dato, ansoegningstype,
     afstandskriterie_dato, afstandskriterie_klassetrin,
     begrundelse_fra_formular, created_by, updated_by, aktiv)
VALUES
(
    '0909101234', '0000C127-AB48-48C7-9770-EDA49D39EB5A', @status_kommende, @matrikel_9, NULL,
    @hjemmel_1, @afgoerelsesbrev_6, @slut_naeste, NULL,
    'ESDH-TEST-009', @sagsbehandler_1, @ppr_2,
    DATEADD(MONTH, -1, @i_dag), NULL, 'Mor',
    @start_naeste, 'Fast kørsel',
    @slut_naeste, 3,
    'Afstand', 'test_seed', 'test_seed', 1
);
DECLARE @bevilling_9 int = SCOPE_IDENTITY();


-- 10: Peter — Udløbet
INSERT INTO [befordring].[Bevilling]
    (cpr_elev, adresse_id, status_id, matrikel_id, ungdomsuddannelse_id,
     hjemmel_id, afgoerelsesbrev_id, revurderingsdato, befordringsudvalg,
     esdh_noegle, sagsbehandler_id, ppr_sagsbehandler_id,
     ansoegningsdato, sagsbehandlingsdato, relation_til_barnet,
     foerste_koersel_dato, ansoegningstype,
     afstandskriterie_dato, afstandskriterie_klassetrin,
     begrundelse_fra_formular, created_by, updated_by, aktiv)
VALUES
(
    '1010101234', '0000E92C-BB46-4745-A0AE-90950142AF79', @status_udloebet, @matrikel_10, NULL,
    @hjemmel_2, @afgoerelsesbrev_8, @slut_sidste, DATEADD(DAY, -20, @slut_sidste),
    'ESDH-TEST-010', @sagsbehandler_2, @ppr_1,
    DATEADD(MONTH, -16, @i_dag), NULL, 'Far',
    @start_sidste, 'Fast kørsel',
    @slut_sidste, 7,
    'Sygdom', 'test_seed', 'test_seed', 1
);
DECLARE @bevilling_10 int = SCOPE_IDENTITY();


-- 11: Emma — Fejlet
INSERT INTO [befordring].[Bevilling]
    (cpr_elev, adresse_id, status_id, matrikel_id, ungdomsuddannelse_id,
     hjemmel_id, afgoerelsesbrev_id, revurderingsdato, befordringsudvalg,
     esdh_noegle, sagsbehandler_id, ppr_sagsbehandler_id,
     ansoegningsdato, sagsbehandlingsdato, relation_til_barnet,
     foerste_koersel_dato, ansoegningstype,
     afstandskriterie_dato, afstandskriterie_klassetrin,
     begrundelse_fra_formular, created_by, updated_by, aktiv)
VALUES
(
    '1111101234', '0000EE38-A966-4A72-9C34-19B0A32AD367', @status_fejlet, @matrikel_11, NULL,
    @hjemmel_2, NULL, NULL, NULL,
    'ESDH-TEST-011', @sagsbehandler_1, NULL,
    DATEADD(MONTH, -4, @i_dag), NULL, 'Mor',
    DATEADD(MONTH, -3, @i_dag), 'Fast kørsel',
    NULL, 10,
    'Sygdom', 'test_seed', 'test_seed', 1
);


-- 12: Anders — Ophørt
INSERT INTO [befordring].[Bevilling]
    (cpr_elev, adresse_id, status_id, matrikel_id, ungdomsuddannelse_id,
     hjemmel_id, afgoerelsesbrev_id, revurderingsdato, befordringsudvalg,
     esdh_noegle, sagsbehandler_id, ppr_sagsbehandler_id,
     ansoegningsdato, sagsbehandlingsdato, relation_til_barnet,
     foerste_koersel_dato, ansoegningstype,
     afstandskriterie_dato, afstandskriterie_klassetrin,
     begrundelse_fra_formular, created_by, updated_by, aktiv)
VALUES
(
    '1212101234', '0000F131-D663-4434-A585-D30CA601B571', @status_ophoert, @matrikel_12, NULL,
    @hjemmel_1, @afgoerelsesbrev_6, @slut_sidste, NULL,
    'ESDH-TEST-012', @sagsbehandler_2, @ppr_2,
    DATEADD(MONTH, -20, @i_dag), NULL, 'Far',
    @start_sidste, 'Fast kørsel',
    @slut_sidste, 7,
    'Afstand', 'test_seed', 'test_seed', 1
);
DECLARE @bevilling_12 int = SCOPE_IDENTITY();


-- 13: Mette — Aktiv
INSERT INTO [befordring].[Bevilling]
    (cpr_elev, adresse_id, status_id, matrikel_id, ungdomsuddannelse_id,
     hjemmel_id, afgoerelsesbrev_id, revurderingsdato, befordringsudvalg,
     esdh_noegle, sagsbehandler_id, ppr_sagsbehandler_id,
     ansoegningsdato, sagsbehandlingsdato, relation_til_barnet,
     foerste_koersel_dato, ansoegningstype,
     afstandskriterie_dato, afstandskriterie_klassetrin,
     begrundelse_fra_formular, created_by, updated_by, aktiv)
VALUES
(
    '1313101234', '0000F5F4-9278-43A5-9BA8-24C21D76610C', @status_aktiv, NULL, @ungdomsuddannelse_2,
    @hjemmel_2, @afgoerelsesbrev_8, @slut_i_aar, NULL,
    'ESDH-TEST-013', @sagsbehandler_1, @ppr_2,
    DATEADD(MONTH, -8, @i_dag), NULL, 'Mor',
    @start_i_aar, 'Midlertidig kørsel',
    @slut_i_aar, 10,
    'Sygdom', 'test_seed', 'test_seed', 1
);
DECLARE @bevilling_13 int = SCOPE_IDENTITY();


-- 14: Thomas — Aktiv (flagged for revurdering below)
INSERT INTO [befordring].[Bevilling]
    (cpr_elev, adresse_id, status_id, matrikel_id, ungdomsuddannelse_id,
     hjemmel_id, afgoerelsesbrev_id, revurderingsdato, befordringsudvalg,
     esdh_noegle, sagsbehandler_id, ppr_sagsbehandler_id,
     ansoegningsdato, sagsbehandlingsdato, relation_til_barnet,
     foerste_koersel_dato, ansoegningstype,
     afstandskriterie_dato, afstandskriterie_klassetrin,
     begrundelse_fra_formular, created_by, updated_by, aktiv)
VALUES
(
    '1414101234', '0000AAF0-826F-4458-B26F-4317AD2A4979', @status_aktiv, @matrikel_13, NULL,
    @hjemmel_1, @afgoerelsesbrev_6, DATEADD(DAY, 30, @i_dag), DATEADD(DAY, -15, @i_dag),
    'ESDH-TEST-014', @sagsbehandler_2, @ppr_1,
    DATEADD(MONTH, -18, @i_dag), NULL, 'Far',
    @start_sidste, 'Fast kørsel',
    @slut_i_aar, 6,
    'Afstand', 'test_seed', 'test_seed', 1
);
DECLARE @bevilling_14 int = SCOPE_IDENTITY();


/* ============================================================
   Bevilling 15-26 — all at Ny

   Ny is not simply the status written here: usp_recalculate_bevilling_status
   derives it, and the rule is NO complete kørselsrækker and NO
   sagsbehandler_id. Give one of these a kørselsrække and it becomes Aktiv,
   Kommende or Udløbet; give it a sagsbehandler and it becomes Påbegyndt.
   So none of them appears in the Koersel section below, and both
   sagsbehandler_id and ppr_sagsbehandler_id are NULL.

   adresse_id matches the student's own, and matrikel_id matches their
   skolekode, so nothing here is flagged for genbehandling.
============================================================ */

-- 15: Astrid — Ny
INSERT INTO [befordring].[Bevilling]
    (cpr_elev, adresse_id, status_id, matrikel_id, ungdomsuddannelse_id,
     hjemmel_id, afgoerelsesbrev_id, revurderingsdato, befordringsudvalg,
     esdh_noegle, sagsbehandler_id, ppr_sagsbehandler_id,
     ansoegningsdato, sagsbehandlingsdato, relation_til_barnet,
     foerste_koersel_dato, ansoegningstype,
     afstandskriterie_dato, afstandskriterie_klassetrin,
     begrundelse_fra_formular, created_by, updated_by, aktiv)
VALUES
(
    '1515101234', '000021C5-E9EE-411D-B2D8-EC9161780CCD', @status_ny, @matrikel_6, NULL,
    NULL, NULL, NULL, NULL,
    'ESDH-TEST-015', NULL, NULL,
    DATEADD(DAY, -1, @i_dag), NULL, 'Forældremyndighed',
    DATEADD(DAY, 14, @i_dag), 'Fast kørsel',
    NULL, NULL,
    'Afstand', 'test_seed', 'test_seed', 1
);

-- 16: Oliver — Ny
INSERT INTO [befordring].[Bevilling]
    (cpr_elev, adresse_id, status_id, matrikel_id, ungdomsuddannelse_id,
     hjemmel_id, afgoerelsesbrev_id, revurderingsdato, befordringsudvalg,
     esdh_noegle, sagsbehandler_id, ppr_sagsbehandler_id,
     ansoegningsdato, sagsbehandlingsdato, relation_til_barnet,
     foerste_koersel_dato, ansoegningstype,
     afstandskriterie_dato, afstandskriterie_klassetrin,
     begrundelse_fra_formular, created_by, updated_by, aktiv)
VALUES
(
    '1616101234', '00002732-733C-433A-A5DA-A7D428A980CF', @status_ny, @matrikel_7, NULL,
    NULL, NULL, NULL, NULL,
    'ESDH-TEST-016', NULL, NULL,
    DATEADD(DAY, -3, @i_dag), NULL, 'Forældremyndighed',
    DATEADD(DAY, 10, @i_dag), 'Fast kørsel',
    NULL, NULL,
    'Afstand', 'test_seed', 'test_seed', 1
);

-- 17: Freja — Ny
INSERT INTO [befordring].[Bevilling]
    (cpr_elev, adresse_id, status_id, matrikel_id, ungdomsuddannelse_id,
     hjemmel_id, afgoerelsesbrev_id, revurderingsdato, befordringsudvalg,
     esdh_noegle, sagsbehandler_id, ppr_sagsbehandler_id,
     ansoegningsdato, sagsbehandlingsdato, relation_til_barnet,
     foerste_koersel_dato, ansoegningstype,
     afstandskriterie_dato, afstandskriterie_klassetrin,
     begrundelse_fra_formular, created_by, updated_by, aktiv)
VALUES
(
    '1717101234', '00002EC8-9A05-423C-ABF2-3D0F4CCB03E0', @status_ny, @matrikel_8, NULL,
    NULL, NULL, NULL, NULL,
    'ESDH-TEST-017', NULL, NULL,
    DATEADD(DAY, -5, @i_dag), NULL, 'Forældremyndighed',
    DATEADD(DAY, 21, @i_dag), 'Fast kørsel',
    NULL, NULL,
    'Handicap', 'test_seed', 'test_seed', 1
);

-- 18: Noah — Ny
INSERT INTO [befordring].[Bevilling]
    (cpr_elev, adresse_id, status_id, matrikel_id, ungdomsuddannelse_id,
     hjemmel_id, afgoerelsesbrev_id, revurderingsdato, befordringsudvalg,
     esdh_noegle, sagsbehandler_id, ppr_sagsbehandler_id,
     ansoegningsdato, sagsbehandlingsdato, relation_til_barnet,
     foerste_koersel_dato, ansoegningstype,
     afstandskriterie_dato, afstandskriterie_klassetrin,
     begrundelse_fra_formular, created_by, updated_by, aktiv)
VALUES
(
    '1818101234', '000059B7-1FE6-4ED2-8386-D9578B2A8859', @status_ny, @matrikel_9, NULL,
    NULL, NULL, NULL, NULL,
    'ESDH-TEST-018', NULL, NULL,
    DATEADD(DAY, -2, @i_dag), NULL, 'Forældremyndighed',
    DATEADD(DAY, 5, @i_dag), 'Midlertidig kørsel',
    NULL, NULL,
    'Sygdom', 'test_seed', 'test_seed', 1
);

-- 19: Clara — Ny
INSERT INTO [befordring].[Bevilling]
    (cpr_elev, adresse_id, status_id, matrikel_id, ungdomsuddannelse_id,
     hjemmel_id, afgoerelsesbrev_id, revurderingsdato, befordringsudvalg,
     esdh_noegle, sagsbehandler_id, ppr_sagsbehandler_id,
     ansoegningsdato, sagsbehandlingsdato, relation_til_barnet,
     foerste_koersel_dato, ansoegningstype,
     afstandskriterie_dato, afstandskriterie_klassetrin,
     begrundelse_fra_formular, created_by, updated_by, aktiv)
VALUES
(
    '1919101234', '0000670C-4F89-4C07-B77B-F9B82AF01C80', @status_ny, @matrikel_10, NULL,
    NULL, NULL, NULL, NULL,
    'ESDH-TEST-019', NULL, NULL,
    DATEADD(DAY, -8, @i_dag), NULL, 'Forældremyndighed',
    DATEADD(DAY, 28, @i_dag), 'Fast kørsel',
    NULL, NULL,
    'Trafikfarlig skolevej', 'test_seed', 'test_seed', 1
);

-- 20: Villads — Ny
INSERT INTO [befordring].[Bevilling]
    (cpr_elev, adresse_id, status_id, matrikel_id, ungdomsuddannelse_id,
     hjemmel_id, afgoerelsesbrev_id, revurderingsdato, befordringsudvalg,
     esdh_noegle, sagsbehandler_id, ppr_sagsbehandler_id,
     ansoegningsdato, sagsbehandlingsdato, relation_til_barnet,
     foerste_koersel_dato, ansoegningstype,
     afstandskriterie_dato, afstandskriterie_klassetrin,
     begrundelse_fra_formular, created_by, updated_by, aktiv)
VALUES
(
    '2020101234', '00009B67-504C-4FE0-B1D1-39126722DF0F', @status_ny, @matrikel_11, NULL,
    NULL, NULL, NULL, NULL,
    'ESDH-TEST-020', NULL, NULL,
    DATEADD(DAY, -4, @i_dag), NULL, 'Forældremyndighed',
    DATEADD(DAY, 17, @i_dag), 'Fast kørsel',
    NULL, NULL,
    'Afstand', 'test_seed', 'test_seed', 1
);

-- 21: Alma — Ny
INSERT INTO [befordring].[Bevilling]
    (cpr_elev, adresse_id, status_id, matrikel_id, ungdomsuddannelse_id,
     hjemmel_id, afgoerelsesbrev_id, revurderingsdato, befordringsudvalg,
     esdh_noegle, sagsbehandler_id, ppr_sagsbehandler_id,
     ansoegningsdato, sagsbehandlingsdato, relation_til_barnet,
     foerste_koersel_dato, ansoegningstype,
     afstandskriterie_dato, afstandskriterie_klassetrin,
     begrundelse_fra_formular, created_by, updated_by, aktiv)
VALUES
(
    '2121101234', '00009E24-9877-4F17-8020-04A0B29E704F', @status_ny, @matrikel_12, NULL,
    NULL, NULL, NULL, NULL,
    'ESDH-TEST-021', NULL, NULL,
    DATEADD(DAY, -6, @i_dag), NULL, 'Forældremyndighed',
    DATEADD(DAY, 12, @i_dag), 'Fast kørsel',
    NULL, NULL,
    'Handicap', 'test_seed', 'test_seed', 1
);

-- 22: Elias — Ny
INSERT INTO [befordring].[Bevilling]
    (cpr_elev, adresse_id, status_id, matrikel_id, ungdomsuddannelse_id,
     hjemmel_id, afgoerelsesbrev_id, revurderingsdato, befordringsudvalg,
     esdh_noegle, sagsbehandler_id, ppr_sagsbehandler_id,
     ansoegningsdato, sagsbehandlingsdato, relation_til_barnet,
     foerste_koersel_dato, ansoegningstype,
     afstandskriterie_dato, afstandskriterie_klassetrin,
     begrundelse_fra_formular, created_by, updated_by, aktiv)
VALUES
(
    '2222101234', '0000AAF0-826F-4458-B26F-4317AD2A4979', @status_ny, @matrikel_13, NULL,
    NULL, NULL, NULL, NULL,
    'ESDH-TEST-022', NULL, NULL,
    DATEADD(DAY, -9, @i_dag), NULL, 'Forældremyndighed',
    DATEADD(DAY, 30, @i_dag), 'Fast kørsel',
    NULL, NULL,
    'Afstand', 'test_seed', 'test_seed', 1
);

-- 23: Ida — Ny
INSERT INTO [befordring].[Bevilling]
    (cpr_elev, adresse_id, status_id, matrikel_id, ungdomsuddannelse_id,
     hjemmel_id, afgoerelsesbrev_id, revurderingsdato, befordringsudvalg,
     esdh_noegle, sagsbehandler_id, ppr_sagsbehandler_id,
     ansoegningsdato, sagsbehandlingsdato, relation_til_barnet,
     foerste_koersel_dato, ansoegningstype,
     afstandskriterie_dato, afstandskriterie_klassetrin,
     begrundelse_fra_formular, created_by, updated_by, aktiv)
VALUES
(
    '2323101234', '0000BF23-21F1-4FBB-85AE-3089BC6CF623', @status_ny, @matrikel_1, NULL,
    NULL, NULL, NULL, NULL,
    'ESDH-TEST-023', NULL, NULL,
    DATEADD(DAY, -1, @i_dag), NULL, 'Forældremyndighed',
    DATEADD(DAY, 3, @i_dag), 'Midlertidig kørsel',
    NULL, NULL,
    'Brækket ben', 'test_seed', 'test_seed', 1
);

-- 24: Malthe — Ny
INSERT INTO [befordring].[Bevilling]
    (cpr_elev, adresse_id, status_id, matrikel_id, ungdomsuddannelse_id,
     hjemmel_id, afgoerelsesbrev_id, revurderingsdato, befordringsudvalg,
     esdh_noegle, sagsbehandler_id, ppr_sagsbehandler_id,
     ansoegningsdato, sagsbehandlingsdato, relation_til_barnet,
     foerste_koersel_dato, ansoegningstype,
     afstandskriterie_dato, afstandskriterie_klassetrin,
     begrundelse_fra_formular, created_by, updated_by, aktiv)
VALUES
(
    '2424101234', '0000C127-AB48-48C7-9770-EDA49D39EB5A', @status_ny, NULL, @ungdomsuddannelse_2,
    NULL, NULL, NULL, NULL,
    'ESDH-TEST-024', NULL, NULL,
    DATEADD(DAY, -7, @i_dag), NULL, 'Forældremyndighed',
    DATEADD(DAY, 25, @i_dag), 'Fast kørsel',
    NULL, NULL,
    'Afstand', 'test_seed', 'test_seed', 1
);

-- 25: Liva — Ny
INSERT INTO [befordring].[Bevilling]
    (cpr_elev, adresse_id, status_id, matrikel_id, ungdomsuddannelse_id,
     hjemmel_id, afgoerelsesbrev_id, revurderingsdato, befordringsudvalg,
     esdh_noegle, sagsbehandler_id, ppr_sagsbehandler_id,
     ansoegningsdato, sagsbehandlingsdato, relation_til_barnet,
     foerste_koersel_dato, ansoegningstype,
     afstandskriterie_dato, afstandskriterie_klassetrin,
     begrundelse_fra_formular, created_by, updated_by, aktiv)
VALUES
(
    '2525101234', '0000E92C-BB46-4745-A0AE-90950142AF79', @status_ny, @matrikel_5, NULL,
    NULL, NULL, NULL, NULL,
    'ESDH-TEST-025', NULL, NULL,
    DATEADD(DAY, -11, @i_dag), NULL, 'Forældremyndighed',
    DATEADD(DAY, 19, @i_dag), 'Fast kørsel',
    NULL, NULL,
    'Trafikfarlig skolevej', 'test_seed', 'test_seed', 1
);

-- 26: Storm — Ny
INSERT INTO [befordring].[Bevilling]
    (cpr_elev, adresse_id, status_id, matrikel_id, ungdomsuddannelse_id,
     hjemmel_id, afgoerelsesbrev_id, revurderingsdato, befordringsudvalg,
     esdh_noegle, sagsbehandler_id, ppr_sagsbehandler_id,
     ansoegningsdato, sagsbehandlingsdato, relation_til_barnet,
     foerste_koersel_dato, ansoegningstype,
     afstandskriterie_dato, afstandskriterie_klassetrin,
     begrundelse_fra_formular, created_by, updated_by, aktiv)
VALUES
(
    '2626101234', '0000EE38-A966-4A72-9C34-19B0A32AD367', @status_ny, @matrikel_2, NULL,
    NULL, NULL, NULL, NULL,
    'ESDH-TEST-026', NULL, NULL,
    DATEADD(DAY, -2, @i_dag), NULL, 'Forældremyndighed',
    DATEADD(DAY, 9, @i_dag), 'Fast kørsel',
    NULL, NULL,
    'Afstand', 'test_seed', 'test_seed', 1
);


/* ============================================================
   ESDH-link.

   One hardcoded URL on every seeded bevilling, so the places that render a
   link to the case have something to render: the Sags-ID column on Overblik,
   the bevilling card, and the Forsendelse list.

   In production this is resolved per case by rpa-befordring-kontrol and the
   nightly run — GO's URL carries a per-case system id that cannot be composed
   from esdh_noegle, which is the whole reason the column exists. A single
   shared link is fine for test data: what is being exercised is "does the
   key render as a link", not where the link goes.

   Set as a separate UPDATE rather than a column on 26 INSERTs, so the value
   is in one place when someone wants to change it.
============================================================ */

UPDATE [befordring].[Bevilling]
SET    esdh_url = 'https://ad.go.aarhuskommune.dk'
WHERE  created_by = 'test_seed'
/* A bevilling with no key has nothing to link — and the UI only shows the
   link where the key is there, so a URL without one would never be seen. */
AND    NULLIF(LTRIM(RTRIM(esdh_noegle)), '') IS NOT NULL;
PRINT CONCAT('Bevilling esdh_url: ', @@ROWCOUNT, ' row(s) updated.');


/* ============================================================
   OS2Forms-ansøgningsdata  (migration 029)

   De fleste "Ny"-bevillinger simuleres som om de kom ind gennem OS2Forms, så
   kolonnen har realistisk indhold at se på.

   INTET I BRUGERFLADEN LÆSER DEN ENDNU. Den blev skrevet for at forudfylde
   "+ Ny kørselsrække", og sagsbehandlerne valgte den forudfyldning fra igen i
   oktober 2026 — kørselsrækker oprettes tomme som før. Opsamlingen blev
   bevidst beholdt: den koster ingenting, og den er grundlaget for den
   redigerbare "ønsket kørselstype", der er aftalt men ikke bygget. Uden
   opsamlingen ville de ansøgninger, der kommer ind i mellemtiden, være tabt.

   Rækkerne herunder dækker stadig hver sin form for indhold — én type, flere
   typer, manglende tidspunkt, ukendt type, ødelagt JSON — så den dag noget
   læser feltet, er der data at læse det med.

   os2forms_id skal være unikt (filtreret unikt indeks), derfor en pr. række.
============================================================ */

/* 15 Astrid — én type, ét tidspunkt. Det enkleste indhold. */
UPDATE [befordring].[Bevilling]
SET os2forms_id = 'aaaa0015-0000-4000-8000-000000000015',
    ansoegningsdata = N'{"koerselstyper":[{"befordringstype":"Rutekørsel","tidspunkt":"Morgen"}],"formular":"ny_ansoegning_om_koersel_af_skol","version":1}'
WHERE cpr_elev = '1515101234' AND created_by = 'test_seed';

/* 16 Oliver — én type, begge veje. */
UPDATE [befordring].[Bevilling]
SET os2forms_id = 'aaaa0016-0000-4000-8000-000000000016',
    ansoegningsdata = N'{"koerselstyper":[{"befordringstype":"Egen befordring","tidspunkt":"Morgen og eftermiddag"}],"formular":"ny_ansoegning_om_koersel_af_skol","version":1}'
WHERE cpr_elev = '1616101234' AND created_by = 'test_seed';

/* 17 Freja — skolebusformularen. Typen står ikke som et felt; det at man
   indsender DEN formular er ønsket.
   Ligger på en FAST kørsel med vilje. Skolebus kan ikke optræde på en
   midlertidig: get_ansoegningstype sender kun ny_ansoegning_om_midlertidig_koe
   til "Midlertidig kørsel", alt andet — skolebusformularen med — bliver
   "Fast kørsel". Og availableKoerselstyper skærer skolebus væk på en
   midlertidig bevilling, så kombinationen ville alligevel ikke kunne vælges. */
UPDATE [befordring].[Bevilling]
SET os2forms_id = 'aaaa0017-0000-4000-8000-000000000017',
    ansoegningsdata = N'{"koerselstyper":[{"befordringstype":"Skolebus","tidspunkt":"Morgen og eftermiddag"}],"formular":"ansoegning_om_koersel_med_skoleb","version":1}'
WHERE cpr_elev = '1717101234' AND created_by = 'test_seed';

/* 18 Noah — midlertidig kørsel, type krydset af men intet tidspunkt sat.
   Tidspunkt er null, hvilket IKKE betyder "begge": ansøgeren sagde det ikke. */
UPDATE [befordring].[Bevilling]
SET os2forms_id = 'aaaa0018-0000-4000-8000-000000000018',
    ansoegningsdata = N'{"koerselstyper":[{"befordringstype":"Rutekørsel","tidspunkt":null}],"formular":"ny_ansoegning_om_midlertidig_koe","version":1}'
WHERE cpr_elev = '1818101234' AND created_by = 'test_seed';

/* 19 Clara — to typer, der er enige om tidspunktet. */
UPDATE [befordring].[Bevilling]
SET os2forms_id = 'aaaa0019-0000-4000-8000-000000000019',
    ansoegningsdata = N'{"koerselstyper":[{"befordringstype":"Egen befordring","tidspunkt":"Morgen"},{"befordringstype":"Rutekørsel","tidspunkt":"Morgen"}],"formular":"ny_ansoegning_om_koersel_af_skol","version":1}'
WHERE cpr_elev = '1919101234' AND created_by = 'test_seed';

/* 20 Villads — to typer med hvert sit tidspunkt. */
UPDATE [befordring].[Bevilling]
SET os2forms_id = 'aaaa0020-0000-4000-8000-000000000020',
    ansoegningsdata = N'{"koerselstyper":[{"befordringstype":"Egen befordring","tidspunkt":"Morgen"},{"befordringstype":"Rutekørsel","tidspunkt":"Eftermiddag"}],"formular":"ny_ansoegning_om_koersel_af_skol","version":1}'
WHERE cpr_elev = '2020101234' AND created_by = 'test_seed';

/* 21 Alma — alle tre typer på én ansøgning. */
UPDATE [befordring].[Bevilling]
SET os2forms_id = 'aaaa0021-0000-4000-8000-000000000021',
    ansoegningsdata = N'{"koerselstyper":[{"befordringstype":"Skolerejsekort","tidspunkt":null},{"befordringstype":"Egen befordring","tidspunkt":"Eftermiddag"},{"befordringstype":"Rutekørsel","tidspunkt":"Morgen"}],"formular":"ny_ansoegning_om_koersel_af_skol","version":1}'
WHERE cpr_elev = '2121101234' AND created_by = 'test_seed';

/* 22 Elias — skolerejsekort (uden tidspunkt) + rutekørsel (morgen).
   Skolerejsekortets null betyder "formularen spurgte ikke", ikke "noget
   andet". Den skelnen er nem at tabe for enhver der læser feltet. */
UPDATE [befordring].[Bevilling]
SET os2forms_id = 'aaaa0022-0000-4000-8000-000000000022',
    ansoegningsdata = N'{"koerselstyper":[{"befordringstype":"Skolerejsekort","tidspunkt":null},{"befordringstype":"Rutekørsel","tidspunkt":"Morgen"}],"formular":"ny_ansoegning_om_koersel_af_skol","version":1}'
WHERE cpr_elev = '2222101234' AND created_by = 'test_seed';

/* 23 Ida — MIDLERTIDIG kørsel, skolerejsekort alene. Formularen spørger ikke
   om tidspunkt for skolerejsekort.
   Skolerejsekort er på MIDLERTIDIG_ALLOWED, så typen er gyldig på en
   midlertidig bevilling. Sammenlign med 18 Noah, der er den anden
   midlertidige. */
UPDATE [befordring].[Bevilling]
SET os2forms_id = 'aaaa0023-0000-4000-8000-000000000023',
    ansoegningsdata = N'{"koerselstyper":[{"befordringstype":"Skolerejsekort","tidspunkt":null}],"formular":"ny_ansoegning_om_midlertidig_koe","version":1}'
WHERE cpr_elev = '2323101234' AND created_by = 'test_seed';

/* 24 Malthe — ungdomsuddannelse, og UDEN ønsket startdato. Viser en
   ansøgning hvor foerste_koersel_dato mangler. */
UPDATE [befordring].[Bevilling]
SET os2forms_id = 'aaaa0024-0000-4000-8000-000000000024',
    foerste_koersel_dato = NULL,
    ansoegningsdata = N'{"koerselstyper":[{"befordringstype":"Egen befordring","tidspunkt":"Morgen og eftermiddag"}],"formular":"ny_ansoegning_om_koersel_af_skol","version":1}'
WHERE cpr_elev = '2424101234' AND created_by = 'test_seed';

/* 25 Liva — en kørselstype der ikke findes i opslagstabellen. Kan opstå
   hvis formularen får en ny mulighed, før opslagstabellen gør. Enhver der
   læser feltet skal kunne tåle det. */
UPDATE [befordring].[Bevilling]
SET os2forms_id = 'aaaa0025-0000-4000-8000-000000000025',
    ansoegningsdata = N'{"koerselstyper":[{"befordringstype":"Ladcykelkørsel","tidspunkt":"Morgen"}],"formular":"ny_ansoegning_om_koersel_af_skol","version":1}'
WHERE cpr_elev = '2525101234' AND created_by = 'test_seed';

/* 26 Storm — ødelagt JSON. Kolonnen er fri tekst for databasen, så enhver
   læser skal kunne parse forgæves uden at vælte. */
UPDATE [befordring].[Bevilling]
SET os2forms_id = 'aaaa0026-0000-4000-8000-000000000026',
    ansoegningsdata = N'{"koerselstyper":[{"befordringstype":'
WHERE cpr_elev = '2626101234' AND created_by = 'test_seed';

/* 1 Kasper — AKTIV bevilling der allerede HAR kørselsrækker, med to ønskede
   typer. Viser at ansøgningsdata og de faktiske kørselsrækker er to
   forskellige ting: hvad der blev ansøgt om, og hvad der blev bevilget. */
UPDATE [befordring].[Bevilling]
SET os2forms_id = 'aaaa0001-0000-4000-8000-000000000001',
    ansoegningsdata = N'{"koerselstyper":[{"befordringstype":"Rutekørsel","tidspunkt":"Morgen"},{"befordringstype":"Egen befordring","tidspunkt":"Eftermiddag"}],"formular":"ny_ansoegning_om_koersel_af_skol","version":1}'
WHERE cpr_elev = '0101101234' AND created_by = 'test_seed';

/* 5 Janni og 6 Jakob får BEVIDST ingen ansøgningsdata: de står for de
   bevillinger en sagsbehandler har oprettet i hånden, og for alt fra før
   migration 029. Kolonnen er NULL på dem, og det skal enhver læser kunne
   tåle — det er flertallet af rækkerne i produktion. */

PRINT 'Bevilling ansoegningsdata: 13 row(s) updated (12 ansoegningsdata-cases + 1 kontrol).';


/* ============================================================
   Revurdering flag (Revurdering is a flag now, not a status).
   Rikke, Rasmus, Thomas are active bevillinger flagged for
   reassessment. Their kørsler are active (see Koersel below) and
   revurderingsdato is approaching, so they would also be flagged
   by usp_recalculate_bevilling_status if it is run.
============================================================ */

UPDATE [befordring].[Bevilling]
SET revurdering = 1
WHERE cpr_elev IN ('0303101234', '0404101234', '1414101234');

-- Genbehandling: Kristian has a skolekode mismatch (test case)
UPDATE [befordring].[Bevilling]
SET genbehandling = 1,
    genbehandling_bemaerkning = N'Skolekode på bevilling matcher ikke elevens aktuelle skolekode'
WHERE cpr_elev = '0202101234';


/* ============================================================
   Bevilling_Hjaelpemiddel_LINK
============================================================ */

INSERT INTO [befordring].[Bevilling_Hjaelpemiddel_LINK] (bevilling_id, hjaelpemiddel_id)
VALUES
-- Kasper: kørestol + co-driver selepakke
(@bevilling_1,  @hjaelpemiddel_koerestol),
-- Kristian: krykker
(@bevilling_2,  @hjaelpemiddel_krykker),
-- Rikke: magnetsele + krampeplan
(@bevilling_3,  @hjaelpemiddel_magnetsele),
(@bevilling_3,  @hjaelpemiddel_krampeplan),
-- Emma: autostol (årsag til specialkørselsbehov)
-- bevilling_11 har ikke SCOPE_IDENTITY, indsæt via subquery
((SELECT TOP 1 bevilling_id FROM [befordring].[Bevilling] WHERE cpr_elev = '1111101234' ORDER BY bevilling_id DESC), @hjaelpemiddel_autostol),
-- Mette: selekappe
(@bevilling_13, @hjaelpemiddel_selekappe);


/* ============================================================
   Koersel
============================================================ */

-- Kasper: aktiv rutekørsel, mellem hjem og skole (sortering 1)
INSERT INTO [befordring].[Koersel]
    (bevilling_id, gyldig_fra, gyldig_til, befordringstype_id,
     bevilget_koereafstand_pr_vej, taxa_id, kommentar, final, rutetype_id)
VALUES (@bevilling_1, @start_i_aar, @slut_i_aar, @befordringstype_rute, NULL, 'TAXA-001', 'Rutekørsel hele dagen.', 1, @rutetype_hjem_skole);
DECLARE @koersel_1 int = SCOPE_IDENTITY();

-- Kristian: aktiv skånekørsel, mellem skole, klub, og hjem (sortering 2)
INSERT INTO [befordring].[Koersel]
    (bevilling_id, gyldig_fra, gyldig_til, befordringstype_id,
     bevilget_koereafstand_pr_vej, taxa_id, kommentar, final, rutetype_id)
VALUES (@bevilling_2, @start_i_aar, @slut_i_aar, @befordringstype_skaane, NULL, 'TAXA-002', 'Skånekørsel via klub.', 1, @rutetype_skole_klub_hjem);
DECLARE @koersel_2 int = SCOPE_IDENTITY();

-- Rikke: egenbefordring, mellem hjem og skole (aktiv — revurdering)
INSERT INTO [befordring].[Koersel]
    (bevilling_id, gyldig_fra, gyldig_til, befordringstype_id,
     bevilget_koereafstand_pr_vej, taxa_id, kommentar, final, rutetype_id)
VALUES (@bevilling_3, @start_sidste, @slut_i_aar, @befordringstype_egen, 6.1, NULL, 'Egen befordring hele dagen.', 0, @rutetype_hjem_skole);
DECLARE @koersel_3 int = SCOPE_IDENTITY();

-- Rasmus: rutekørsel alle dage (aktiv — revurdering)
INSERT INTO [befordring].[Koersel]
    (bevilling_id, gyldig_fra, gyldig_til, befordringstype_id,
     bevilget_koereafstand_pr_vej, taxa_id, kommentar, final, rutetype_id)
VALUES (@bevilling_4, @start_i_aar, @slut_i_aar, @befordringstype_rute, NULL, 'TAXA-003', 'Rutekørsel alle dage.', 0, @rutetype_hjem_skole);
DECLARE @koersel_4 int = SCOPE_IDENTITY();

-- Sofie: kommende skolerejsekort, fra hjem til skole (sortering 3)
INSERT INTO [befordring].[Koersel]
    (bevilling_id, gyldig_fra, gyldig_til, befordringstype_id,
     bevilget_koereafstand_pr_vej, taxa_id, kommentar, final, rutetype_id)
VALUES (@bevilling_9, @start_naeste, @slut_naeste, @befordringstype_rejsekort, NULL, NULL, 'Skolerejsekort, kun ud om morgenen.', 0, @rutetype_fra_hjem_skole);
DECLARE @koersel_9 int = SCOPE_IDENTITY();

-- Peter: udløbet rutekørsel (forrige skoleår)
INSERT INTO [befordring].[Koersel]
    (bevilling_id, gyldig_fra, gyldig_til, befordringstype_id,
     bevilget_koereafstand_pr_vej, taxa_id, kommentar, final, rutetype_id)
VALUES (@bevilling_10, @start_sidste, @slut_sidste, @befordringstype_rute, NULL, 'TAXA-010', 'Udløbet rutekørsel.', 1, @rutetype_hjem_skole);
DECLARE @koersel_10 int = SCOPE_IDENTITY();

-- Anders: ophørt rutekørsel (afsluttet da eleven skiftede distrikt)
INSERT INTO [befordring].[Koersel]
    (bevilling_id, gyldig_fra, gyldig_til, befordringstype_id,
     bevilget_koereafstand_pr_vej, taxa_id, kommentar, final, rutetype_id)
VALUES (@bevilling_12, @start_sidste, DATEADD(MONTH, 5, @start_sidste), @befordringstype_rute, NULL, 'TAXA-012', 'Ophørt rutekørsel.', 1, @rutetype_hjem_skole);
DECLARE @koersel_12 int = SCOPE_IDENTITY();

-- Mette: aktiv egenbefordring til ungdomsuddannelse
INSERT INTO [befordring].[Koersel]
    (bevilling_id, gyldig_fra, gyldig_til, befordringstype_id,
     bevilget_koereafstand_pr_vej, taxa_id, kommentar, final, rutetype_id)
VALUES (@bevilling_13, @start_i_aar, @slut_i_aar, @befordringstype_egen, 12.1, NULL, 'Egen befordring morgen til Diakonhøjskolen.', 1, @rutetype_hjem_skole);
DECLARE @koersel_13 int = SCOPE_IDENTITY();

-- Thomas: rutekørsel (aktiv — revurdering)
INSERT INTO [befordring].[Koersel]
    (bevilling_id, gyldig_fra, gyldig_til, befordringstype_id,
     bevilget_koereafstand_pr_vej, taxa_id, kommentar, final, rutetype_id)
VALUES (@bevilling_14, @start_sidste, @slut_i_aar, @befordringstype_rute, NULL, 'TAXA-014', 'Rutekørsel hele dagen — bevilling under revurdering.', 0, @rutetype_hjem_skole);
DECLARE @koersel_14 int = SCOPE_IDENTITY();


/* ------------------------------------------------------------
   Thomas, fortsat: tre rækker med PRÆCIS samme datoer

   Findes udelukkende for at vise rutetype-sorteringen. Når gyldig_fra og
   gyldig_til er ens, falder datosorteringen igennem, og
   Rutetype.sorteringsorden afgør rækkefølgen (migration 032).

   Rækkerne er indsat i OMVENDT rækkefølge med vilje — 6, 5, 4 — oven i
   @koersel_14, der er sortering 1. Vises de i rækkefølgen

       mellem hjem og skole (1)
       fra skole til klub   (4)
       fra skole til hjem   (5)
       fra klub til hjem    (6)

   så virker sorteringen. Kommer de i indsætningsrækkefølge, gør den ikke.
   Gælder både kørselsrækkekortet og afgørelsesbrevet, som nu sorterer ens.
------------------------------------------------------------ */

INSERT INTO [befordring].[Koersel]
    (bevilling_id, gyldig_fra, gyldig_til, befordringstype_id,
     bevilget_koereafstand_pr_vej, taxa_id, kommentar, final, rutetype_id)
VALUES (@bevilling_14, @start_sidste, @slut_i_aar, @befordringstype_rute, NULL, 'TAXA-014', 'Sorteringstest: indsat først, skal vises sidst.', 0, @rutetype_fra_klub_hjem);
DECLARE @koersel_14b int = SCOPE_IDENTITY();

INSERT INTO [befordring].[Koersel]
    (bevilling_id, gyldig_fra, gyldig_til, befordringstype_id,
     bevilget_koereafstand_pr_vej, taxa_id, kommentar, final, rutetype_id)
VALUES (@bevilling_14, @start_sidste, @slut_i_aar, @befordringstype_rute, NULL, 'TAXA-014', 'Sorteringstest: skal vises næstsidst.', 0, @rutetype_fra_skole_hjem);
DECLARE @koersel_14c int = SCOPE_IDENTITY();

INSERT INTO [befordring].[Koersel]
    (bevilling_id, gyldig_fra, gyldig_til, befordringstype_id,
     bevilget_koereafstand_pr_vej, taxa_id, kommentar, final, rutetype_id)
VALUES (@bevilling_14, @start_sidste, @slut_i_aar, @befordringstype_rute, NULL, 'TAXA-014', 'Sorteringstest: skal vises som nummer to.', 0, @rutetype_fra_skole_klub);
DECLARE @koersel_14d int = SCOPE_IDENTITY();


/* ============================================================
   Koersel_KoerselstypeTillaeg_LINK
============================================================ */

INSERT INTO [befordring].[Koersel_KoerselstypeTillaeg_LINK] (koersel_id, tillaeg_id)
VALUES
(@koersel_1,  @tillaeg_fast_forsaede),
(@koersel_1,  @tillaeg_co_driver),
(@koersel_2,  @tillaeg_egen_ledsager),
(@koersel_4,  @tillaeg_fast_saede),
(@koersel_10, @tillaeg_fast_forsaede),
(@koersel_14, @tillaeg_fast_saede);


/* ============================================================
   Koersel_Ugedag_LINK
============================================================ */

INSERT INTO [befordring].[Koersel_Ugedag_LINK] (koersel_id, dag_id)
VALUES
-- Kasper: alle dage
(@koersel_1,  @dag_alle),

-- Kristian: man, ons, fre
(@koersel_2,  @dag_mandag),
(@koersel_2,  @dag_onsdag),
(@koersel_2,  @dag_fredag),

-- Rikke: tirs + tors
(@koersel_3,  @dag_tirsdag),
(@koersel_3,  @dag_torsdag),

-- Rasmus: alle dage
(@koersel_4,  @dag_alle),

-- Sofie: alle dage (skolerejsekort)
(@koersel_9,  @dag_alle),

-- Peter: alle dage (historisk)
(@koersel_10, @dag_alle),

-- Anders: alle dage (historisk)
(@koersel_12, @dag_alle),

-- Mette: man–fre morgen
(@koersel_13, @dag_mandag),
(@koersel_13, @dag_tirsdag),
(@koersel_13, @dag_onsdag),
(@koersel_13, @dag_torsdag),
(@koersel_13, @dag_fredag),

-- Thomas: alle dage
(@koersel_14,  @dag_alle),
(@koersel_14b, @dag_alle),
(@koersel_14c, @dag_alle),
(@koersel_14d, @dag_alle);



/* ============================================================
   Sagsaktivitet  (case-activity audit log → "Sagsforløb" feed)

   Mirrors the event types the application itself writes so the
   test feed looks like real usage:
     Bevilling oprettet · Sagsbehandler opdateret ·
     PPR ansvarlig opdateret · PPR/BR Revurderet ·
     Status sat til <status> · Brev oprettet · Kommentar

   udfoert_af = 'System' for automated/SP-driven events,
   or a caseworker name for manual actions.

   Timestamps are explicit so the feed renders in a realistic
   chronological order.
============================================================ */

INSERT INTO [befordring].[Sagsaktivitet]
    (cpr, aktivitetstype, kommentar, udfoert_af, oprettet_tidspunkt, relateret_bevilling_id)
VALUES
-- Kasper (Aktiv) — full happy-path lifecycle
('0101101234', 'Bevilling oprettet',       CONCAT('Bevilling ID: ', @bevilling_1, ' — Status: Ny'), 'System', DATEADD(MINUTE, 555, DATEADD(DAY, -215, @nu)), @bevilling_1),
('0101101234', 'Sagsbehandler opdateret',  'Sagsbehandler sat til Sofie',               'Sofie',  DATEADD(MINUTE, 600, DATEADD(DAY, -206, @nu)), @bevilling_1),
('0101101234', 'PPR ansvarlig opdateret',  'PPR ansvarlig sat til Hans',                'Sofie',  DATEADD(MINUTE, 605, DATEADD(DAY, -206, @nu)), @bevilling_1),
('0101101234', 'Status sat til Påbegyndt', 'Sagsbehandler tilføjet',                    'System', DATEADD(MINUTE, 606, DATEADD(DAY, -206, @nu)), @bevilling_1),
('0101101234', 'Status sat til Aktiv',     'Bevillingsperioden er startet',             'System', DATEADD(MINUTE, 360, DATEADD(DAY, -185, @nu)), @bevilling_1),
('0101101234', 'Kommentar',                'Forælder har bekræftet taxaordningen.',     'Sofie',  DATEADD(MINUTE, 800, DATEADD(DAY, -171, @nu)), @bevilling_1),

-- Laura (Påbegyndt)
('0707101234', 'Bevilling oprettet',       'Bevilling oprettet fra ansøgning.',         'System', DATEADD(MINUTE, 510, DATEADD(DAY, -24, @nu)), (SELECT TOP 1 bevilling_id FROM [befordring].[Bevilling] WHERE cpr_elev = '0707101234' ORDER BY bevilling_id DESC)),
('0707101234', 'Sagsbehandler opdateret',  'Sagsbehandler sat til Sofie',               'Sofie',  DATEADD(MINUTE, 540, DATEADD(DAY, -10, @nu)), (SELECT TOP 1 bevilling_id FROM [befordring].[Bevilling] WHERE cpr_elev = '0707101234' ORDER BY bevilling_id DESC)),
('0707101234', 'Status sat til Påbegyndt', 'Sagsbehandler tilføjet',                    'System', DATEADD(MINUTE, 541, DATEADD(DAY, -10, @nu)), (SELECT TOP 1 bevilling_id FROM [befordring].[Bevilling] WHERE cpr_elev = '0707101234' ORDER BY bevilling_id DESC)),

-- Sofie Lund (Kommende)
('0909101234', 'Bevilling oprettet',       CONCAT('Bevilling ID: ', @bevilling_9, ' — Status: Ny'), 'System', DATEADD(MINUTE, 660, DATEADD(DAY, -30, @nu)), @bevilling_9),
('0909101234', 'Sagsbehandler opdateret',  'Sagsbehandler sat til Sofie',               'Sofie',  DATEADD(MINUTE, 570, DATEADD(DAY, -20, @nu)), @bevilling_9),
('0909101234', 'Status sat til Kommende',  'Bevillingsperioden er endnu ikke startet',  'System', DATEADD(MINUTE, 571, DATEADD(DAY, -20, @nu)), @bevilling_9),

-- Rikke (revurdering) — PPR reviewed, awaiting BR
('0303101234', 'Bevilling oprettet',       CONCAT('Bevilling ID: ', @bevilling_3, ' — Status: Ny'), 'System', DATEADD(MINUTE, 480, DATEADD(DAY, -430, @nu)), @bevilling_3),
('0303101234', 'Sagsbehandler opdateret',  'Sagsbehandler sat til Sofie',               'Sofie',  DATEADD(MINUTE, 600, DATEADD(DAY, -420, @nu)), @bevilling_3),
('0303101234', 'Status sat til Aktiv',     'Bevillingsperioden er startet',             'System', DATEADD(MINUTE, 360, DATEADD(DAY, -400, @nu)), @bevilling_3),
('0303101234', 'PPR Revurderet',           NULL,                                        'Sofie',  DATEADD(MINUTE, 840, DATEADD(DAY, -26, @nu)), @bevilling_3),
('0303101234', 'Kommentar',                'Afventer BR-gennemgang pga. adressebeskyttelse.', 'Sofie', DATEADD(MINUTE, 910, DATEADD(DAY, -12, @nu)), @bevilling_3),

-- Rasmus (revurdering)
('0404101234', 'Bevilling oprettet',       CONCAT('Bevilling ID: ', @bevilling_4, ' — Status: Ny'), 'System', DATEADD(MINUTE, 540, DATEADD(DAY, -280, @nu)), @bevilling_4),
('0404101234', 'Sagsbehandler opdateret',  'Sagsbehandler sat til Nina',                'Nina',   DATEADD(MINUTE, 630, DATEADD(DAY, -271, @nu)), @bevilling_4),
('0404101234', 'PPR Revurderet',           NULL,                                        'Nina',   DATEADD(MINUTE, 825, DATEADD(DAY, -40, @nu)), @bevilling_4),

-- Thomas (revurdering) — PPR done, forwarded to BR
('1414101234', 'Bevilling oprettet',       CONCAT('Bevilling ID: ', @bevilling_14, ' — Status: Ny'), 'System', DATEADD(MINUTE, 495, DATEADD(DAY, -548, @nu)), @bevilling_14),
('1414101234', 'Sagsbehandler opdateret',  'Sagsbehandler sat til Nina',                'Nina',   DATEADD(MINUTE, 660, DATEADD(DAY, -534, @nu)), @bevilling_14),
('1414101234', 'Status sat til Aktiv',     'Bevillingsperioden er startet',             'System', DATEADD(MINUTE, 360, DATEADD(DAY, -400, @nu)), @bevilling_14),
('1414101234', 'PPR Revurderet',           NULL,                                        'Nina',   DATEADD(MINUTE, 860, DATEADD(DAY, -18, @nu)), @bevilling_14),
('1414101234', 'Kommentar',                'PPR har vurderet sagen; videresendt til BR.', 'Nina', DATEADD(MINUTE, 545, DATEADD(DAY, -17, @nu)), @bevilling_14),

-- Martin (Afslag) — with letter
('0808101234', 'Bevilling oprettet',       'Bevilling oprettet fra ansøgning.',         'System', DATEADD(MINUTE, 480, DATEADD(DAY, -92, @nu)), (SELECT TOP 1 bevilling_id FROM [befordring].[Bevilling] WHERE cpr_elev = '0808101234' ORDER BY bevilling_id DESC)),
('0808101234', 'Status sat til Afslag',    'Afstandskriterie ikke opfyldt.',            'Nina',   DATEADD(MINUTE, 780, DATEADD(DAY, -80, @nu)), (SELECT TOP 1 bevilling_id FROM [befordring].[Bevilling] WHERE cpr_elev = '0808101234' ORDER BY bevilling_id DESC)),
('0808101234', 'Brev oprettet',            'Afslag: § 26, stk. 1, nr. 1 (afstand)',     'Nina',   DATEADD(MINUTE, 630, DATEADD(DAY, -79, @nu)), (SELECT TOP 1 bevilling_id FROM [befordring].[Bevilling] WHERE cpr_elev = '0808101234' ORDER BY bevilling_id DESC)),

-- Peter (Udløbet) — historical lifecycle
('1010101234', 'Bevilling oprettet',       CONCAT('Bevilling ID: ', @bevilling_10, ' — Status: Ny'), 'System', DATEADD(MINUTE, 480, DATEADD(DAY, -500, @nu)), @bevilling_10),
('1010101234', 'Status sat til Aktiv',     'Bevillingsperioden er startet',             'System', DATEADD(MINUTE, 360, DATEADD(DAY, -400, @nu)), @bevilling_10),
('1010101234', 'Status sat til Udløbet',   'Bevillingsperioden er udløbet',             'System', DATEADD(MINUTE, 360, DATEADD(DAY, -76, @nu)), @bevilling_10);


/* ============================================================
   Brev oprettet — decision letters.

   sagsbehandlingsdato is stamped automatically when the caseworker
   creates the letter (see create_letter / set_sagsbehandlingsdato in
   the backend). So every bevilling that reached a decision — Aktiv,
   Udløbet, Ophørt or Afslag — has a 'Brev oprettet' activity, and the
   UPDATE below backfills sagsbehandlingsdato to match each letter's date.
   The kommentar mirrors each bevilling's assigned afgørelsesbrev.
   (Martin's afslag letter is already inserted in the block above.)
============================================================ */

INSERT INTO [befordring].[Sagsaktivitet]
    (cpr, aktivitetstype, kommentar, udfoert_af, oprettet_tidspunkt, relateret_bevilling_id)
VALUES
('0101101234', 'Brev oprettet', 'Bevilling: § 26, stk. 1, nr. 1 (afstand)',            'Sofie', DATEADD(MINUTE, 660, DATEADD(DAY, -200, @nu)), @bevilling_1),
('0202101234', 'Brev oprettet', 'Bevilling: § 26, stk. 2 (sygdom)',                    'Nina',  DATEADD(MINUTE, 630, DATEADD(DAY, -176, @nu)), @bevilling_2),
('0303101234', 'Brev oprettet', 'Bevilling: § 26, stk. 1, nr. 2 (farlig skolevej)',    'Sofie', DATEADD(MINUTE, 795, DATEADD(DAY, -405, @nu)), @bevilling_3),
('0404101234', 'Brev oprettet', 'Afslag: § 26, stk. 6, § 36, stk. 3 (frit skolevalg)', 'Nina',  DATEADD(MINUTE, 585, DATEADD(DAY, -227, @nu)), @bevilling_4),
('1010101234', 'Brev oprettet', 'Bevilling: § 26, stk. 2 (sygdom)',                    'Nina',  DATEADD(MINUTE, 570, DATEADD(DAY, -410, @nu)), @bevilling_10),
('1212101234', 'Brev oprettet', 'Bevilling: § 26, stk. 1, nr. 1 (afstand)',            'Nina',  DATEADD(MINUTE, 510, DATEADD(DAY, -400, @nu)), @bevilling_12),
('1313101234', 'Brev oprettet', 'Bevilling: § 26, stk. 2 (sygdom)',                    'Sofie', DATEADD(MINUTE, 840, DATEADD(DAY, -226, @nu)), @bevilling_13),
('1414101234', 'Brev oprettet', 'Bevilling: § 26, stk. 1, nr. 1 (afstand)',            'Nina',  DATEADD(MINUTE, 600, DATEADD(DAY, -420, @nu)), @bevilling_14);


/* ------------------------------------------------------------
   Events that exist ONLY as a type code

   koerselsraekke_oprettet and brev_afsendt were added after the code
   taxonomy (migrations 024 and 025), so they have no legacy Danish string
   the feed could fall back on. Seeding a couple exercises the path where
   type_kode is the only thing the frontend has to go on — the rows above
   all still carry text that the fallback would match, so without these the
   dev feed would never test it.
------------------------------------------------------------ */

INSERT INTO [befordring].[Sagsaktivitet]
    (cpr, aktivitetstype, kommentar, udfoert_af, oprettet_tidspunkt, relateret_bevilling_id)
VALUES
('0101101234', 'Kørselsrække oprettet', 'Kørselsrække tilføjet til bevillingen.', 'Sofie', DATEADD(MINUTE, 620, DATEADD(DAY, -184, @nu)), @bevilling_1),
('0101101234', 'Brev afsendt',          'Bevillingsbrev markeret som afsendt.',   'Sofie', DATEADD(MINUTE, 640, DATEADD(DAY, -180, @nu)), @bevilling_1),
('1212101234', 'Brev afsendt',          'Bevillingsbrev markeret som afsendt.',   'Nina',  DATEADD(MINUTE, 530, DATEADD(DAY, -399, @nu)), @bevilling_12),

-- Deliberately unmapped: no type_kode will match this text, so the row keeps
-- aktivitetstype_id NULL. That is the state of every row written before
-- migration 023, and the feed has to render it from the text alone.
('0707101234', 'Ukendt hændelse',       'Række uden kendt type — falder tilbage på teksten.', 'System', DATEADD(MINUTE, 700, DATEADD(DAY, -9, @nu)), (SELECT TOP 1 bevilling_id FROM [befordring].[Bevilling] WHERE cpr_elev = '0707101234' ORDER BY bevilling_id DESC));


/* ------------------------------------------------------------
   Resolve aktivitetstype_id from the text

   The same mapping migration 023 uses, applied here so the test data looks
   like a database that has been through it. Done as an UPDATE rather than a
   column on every VALUES row: the rows above stay readable, and a row added
   later is covered without anyone remembering to set the id by hand.

   A text matching no code keeps NULL — see the row seeded for exactly that.
------------------------------------------------------------ */

UPDATE sa
SET    sa.aktivitetstype_id = t.type_id
FROM       [befordring].[Sagsaktivitet]     sa
INNER JOIN [befordring].[SagsaktivitetType] t ON t.type_kode = CASE
    WHEN sa.aktivitetstype = N'Bevilling oprettet'        THEN N'bevilling_oprettet'
    WHEN sa.aktivitetstype = N'Bevilling slettet'         THEN N'bevilling_slettet'
    WHEN sa.aktivitetstype = N'Brev oprettet'             THEN N'brev_oprettet'
    WHEN sa.aktivitetstype = N'Brev afsendt'              THEN N'brev_afsendt'
    WHEN sa.aktivitetstype = N'Kørselsrække oprettet'     THEN N'koerselsraekke_oprettet'
    WHEN sa.aktivitetstype = N'Kørselsrække slettet'      THEN N'koerselsraekke_slettet'
    WHEN sa.aktivitetstype LIKE N'Status sat til %'       THEN N'status_opdateret'
    WHEN sa.aktivitetstype = N'Sagsbehandler opdateret'   THEN N'sagsbehandler_opdateret'
    WHEN sa.aktivitetstype = N'PPR ansvarlig opdateret'   THEN N'ppr_ansvarlig_opdateret'
    WHEN sa.aktivitetstype = N'PPR Revurderet'            THEN N'ppr_revurderet'
    WHEN sa.aktivitetstype = N'PPR revurderet fjernet'    THEN N'ppr_revurderet_fjernet'
    WHEN sa.aktivitetstype = N'BR Revurderet'             THEN N'br_revurderet'
    WHEN sa.aktivitetstype = N'BR revurderet fjernet'     THEN N'br_revurderet_fjernet'
    WHEN sa.aktivitetstype = N'Bevilling sat til Ophørt'  THEN N'bevilling_ophoert'
    WHEN sa.aktivitetstype = N'Kommentar'                 THEN N'kommentar'
    ELSE NULL
END
WHERE sa.aktivitetstype_id IS NULL;
PRINT CONCAT('Sagsaktivitet: satte aktivitetstype_id på ', @@ROWCOUNT, ' række(r).');


/* ============================================================
   Backfill sagsbehandlingsdato from each bevilling's letter date.
   Mirrors the runtime behaviour: the case is processed on the day its
   decision letter is created. Uses the latest 'Brev oprettet' activity
   per bevilling (there is one each here).
============================================================ */

UPDATE b
SET b.sagsbehandlingsdato = CONVERT(date, la.letter_dato)
FROM [befordring].[Bevilling] b
INNER JOIN (
    SELECT
        relateret_bevilling_id,
        MAX(oprettet_tidspunkt) AS letter_dato
    FROM [befordring].[Sagsaktivitet]
    WHERE aktivitetstype = 'Brev oprettet'
      AND relateret_bevilling_id IS NOT NULL
    GROUP BY relateret_bevilling_id
) la ON la.relateret_bevilling_id = b.bevilling_id;


/* ============================================================
   Quick test selects
============================================================ */

PRINT '';
PRINT 'Inserted test data. Previewing views...';
PRINT '';

SELECT * FROM [befordring].[view_Stamdata];
SELECT * FROM [befordring].[view_Student_Bevillinger];
SELECT * FROM [befordring].[view_Bevilling_Koerselsraekker];
SELECT * FROM [befordring].[view_All_Active_Bevillinger];
SELECT * FROM [befordring].[view_New_Applications];
SELECT * FROM [befordring].[view_Revurderinger];
SELECT * FROM [befordring].[view_Genbehandling];
SELECT   sa.aktivitet_id, sa.cpr, sa.aktivitetstype, t.type_kode,
         sa.kommentar, sa.udfoert_af, sa.oprettet_tidspunkt
FROM     [befordring].[Sagsaktivitet] sa
LEFT JOIN [befordring].[SagsaktivitetType] t ON t.type_id = sa.aktivitetstype_id
ORDER BY sa.cpr, sa.oprettet_tidspunkt;

PRINT '';
PRINT 'ROLLBACK is active. Change to COMMIT when the data looks correct.';
PRINT '';

ROLLBACK TRANSACTION;
