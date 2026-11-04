/* ============================================================
   Lookup / reference data for the befordring schema.

   Everything the application needs in order to run, and nothing about any
   individual citizen: statuses, kørselstyper, hjemler, afgørelsesbreve,
   skolematrikler, ugedage and so on. No Elev, Foraelder, Part, Bevilling,
   Koersel, Sagsaktivitet or Brev rows are created here — for those, see
   seed_test_data.sql, which is test data and is NOT for a real environment.

   DESTRUCTIVE, like seed_test_data.sql: it CLEARS every lookup table,
   reseeds their identities and inserts the whole set. The file is therefore
   the definition of what the lookups contain, not a list of additions to
   them — what you read here is exactly what the database ends up with, and
   a row deleted from this file disappears from the database on the next run.

   The previous version only ever added, guarded row by row on NOT EXISTS.
   That kept identity values stable, but it also meant the file and the
   database could disagree indefinitely: a corrected beskrivelse was ignored
   because the natural key already existed, and a row removed here lived on.
   Reading the file told you what a FRESH database would get, not what any
   real one held.

   WHAT THIS COSTS: identity values change. Every lookup id is reassigned
   from 1 in the order the rows appear below, so anything holding a foreign
   key into these tables must be gone first. The guard below refuses to run
   while such rows exist rather than letting the deletes fail half way
   through with a foreign-key error that names no way forward.

   So this is for a fresh or reset database. To rebuild a populated one:

       1. reset_lookup_data.sql   clears application data and lookups
       2. this script             reinserts the lookups
       3. the nightly run         restores Elev.matrikel_id from the
                                  bevillinger, if any survive

   NOT SEEDED: Sagsbehandler and PPR_Sagsbehandler. Those are real people,
   not reference data — they are created and retired as staff come and go,
   and a hardcoded list here would quietly reintroduce someone who had left,
   or make a fresh database look correct while naming the wrong caseworkers.
   Both are still counted by the verification at the bottom, because an empty
   Sagsbehandler table is a working database the conversion bot cannot run
   against. A table marked * there is one this script does not manage.

   Runs inside a transaction that ROLLBACKs by default — change the final
   ROLLBACK to COMMIT once the previewed counts look correct. The
   verification selects at the bottom run BEFORE that decision, so they show
   what the commit would leave behind.

   Requires migrations 001-025 (Rutetype arrives in 003, SagsaktivitetType
   in 023).
   ============================================================ */

USE [Befordringssystemet];

SET NOCOUNT ON;

-- Any error aborts the batch and rolls the transaction back, so a failure
-- part-way cannot leave some lookup tables populated and others empty.
SET XACT_ABORT ON;

BEGIN TRANSACTION;


/* ------------------------------------------------------------
   0. Refuse to run while anything references the lookups

   Reassigning every lookup id under a live Bevilling or Koersel would
   silently repoint it at a different status, kørselstype or school. The
   deletes below would fail on the foreign keys anyway — this just fails
   first, and says what to do about it.
------------------------------------------------------------ */

DECLARE @blokerende NVARCHAR(MAX) = N'';

SELECT @blokerende = STRING_AGG(x.tabel + N' (' + CAST(x.antal AS NVARCHAR(20)) + N')', N', ')
FROM (
    SELECT N'Bevilling' AS tabel, COUNT(*) AS antal FROM [befordring].[Bevilling]
    UNION ALL SELECT N'Koersel',  COUNT(*) FROM [befordring].[Koersel]
) x
WHERE x.antal > 0;

IF @blokerende <> N''
BEGIN
    ROLLBACK TRANSACTION;

    RAISERROR(
        N'Cannot reseed the lookup tables: %s still reference them. This script reassigns every lookup id from 1, which would repoint those rows at different statuses, koerselstyper and schools. Run reset_lookup_data.sql first, or use seed_test_data.sql if this is a dev database being rebuilt from scratch.',
        16, 1, @blokerende
    );

    RETURN;
END;


/* ------------------------------------------------------------
   1. Release Elev's references into the lookups about to be cleared

   FK_Elev_Skolematrikel and FK_Elev_Ungdomsuddannelse would otherwise block
   the deletes. NULL is the right value rather than something to preserve:
   with no bevillinger left, usp_sync_elev_matrikel_from_bevilling would
   clear both columns on its next run in any case. It derives them again once
   bevillinger exist.
------------------------------------------------------------ */

UPDATE [befordring].[Elev]
SET    matrikel_id          = NULL,
       ungdomsuddannelse_id = NULL
WHERE  matrikel_id IS NOT NULL
OR     ungdomsuddannelse_id IS NOT NULL;

PRINT CONCAT('Released school references on ', @@ROWCOUNT, ' elev(er).');

/* FK_Sagsaktivitet_Type blocks the SagsaktivitetType delete the same way.
   NULL is the right value here too: aktivitetstype still carries the display
   text, so the Sagsforløb feed falls back to matching that — which is exactly
   what it does for rows written before migration 023. The codes are
   reassigned below, and the ids are not stable across a reseed, so keeping
   the old ones would be worse than clearing them. */
UPDATE [befordring].[Sagsaktivitet]
SET    aktivitetstype_id = NULL
WHERE  aktivitetstype_id IS NOT NULL;

PRINT CONCAT('Released activity types on ', @@ROWCOUNT, ' sagsaktivitet(er).');


/* ------------------------------------------------------------
   2. Clear every lookup table, then restart their identities

   Order does not matter among these — the lookups do not reference each
   other — but they are listed alphabetically so a table added later has an
   obvious place to go.
------------------------------------------------------------ */

DELETE FROM [befordring].[Afgoerelsesbrev];
DELETE FROM [befordring].[Befordringstype];
DELETE FROM [befordring].[Hjaelpemiddel];
DELETE FROM [befordring].[Hjemmel];
DELETE FROM [befordring].[KoerselstypeTillaeg];
DELETE FROM [befordring].[Rutetype];
DELETE FROM [befordring].[SagsaktivitetType];
DELETE FROM [befordring].[Skolematrikel];
DELETE FROM [befordring].[Status];
DELETE FROM [befordring].[Tidspunkt];
DELETE FROM [befordring].[Ugedag];
DELETE FROM [befordring].[Ungdomsuddannelse];

PRINT 'Cleared lookup data.';

/* RESEED, 0 rather than a bare RESEED: on an empty table a bare RESEED
   leaves the current identity where it was, so the next insert would carry
   on from the old numbering. The repair block after the transaction puts
   every counter back in step with whatever the tables actually hold, which
   matters because DBCC CHECKIDENT is NOT transactional — a ROLLBACK below
   restores the rows but would leave these counters at 0. */
DBCC CHECKIDENT ('[befordring].[Afgoerelsesbrev]',    RESEED, 0);
DBCC CHECKIDENT ('[befordring].[Befordringstype]',    RESEED, 0);
DBCC CHECKIDENT ('[befordring].[Hjaelpemiddel]',      RESEED, 0);
DBCC CHECKIDENT ('[befordring].[Hjemmel]',            RESEED, 0);
DBCC CHECKIDENT ('[befordring].[KoerselstypeTillaeg]', RESEED, 0);
DBCC CHECKIDENT ('[befordring].[Rutetype]',           RESEED, 0);
DBCC CHECKIDENT ('[befordring].[SagsaktivitetType]',   RESEED, 0);
DBCC CHECKIDENT ('[befordring].[Skolematrikel]',      RESEED, 0);
DBCC CHECKIDENT ('[befordring].[Status]',             RESEED, 0);
DBCC CHECKIDENT ('[befordring].[Tidspunkt]',          RESEED, 0);
DBCC CHECKIDENT ('[befordring].[Ugedag]',             RESEED, 0);
DBCC CHECKIDENT ('[befordring].[Ungdomsuddannelse]',  RESEED, 0);


PRINT 'Seeding lookup data...';
PRINT '';


-- Status  (8 rows)
INSERT INTO [befordring].[Status] (status_tekst, beskrivelse, aktiv)
SELECT v.status_tekst, v.beskrivelse, v.aktiv
FROM (VALUES
    ('Ny',          'Ny ansøgning',                  1),
    ('Påbegyndt',   'Påbegyndt',                     1),
    ('Afslag',      'Afslag',                        1),
    ('Aktiv',       'Aktiv bevilling eller koersel',  1),
    ('Kommende',    'Kommende',                      1),
    ('Udløbet',     'Udløbet',                       1),
    ('Fejlet',      'Fejlet',                        1),
    ('Ophørt',      'Ophørt',                        1)
) AS v (status_tekst, beskrivelse, aktiv);
PRINT CONCAT('Status: ', @@ROWCOUNT, ' row(s) inserted.');


-- Skolematrikel  (56 rows)
INSERT INTO [befordring].[Skolematrikel] (matrikel_navn, matrikel_adresse, skolekode, er_matrikel_hovedadresse, latitude, longitude)
SELECT v.matrikel_navn, v.matrikel_adresse, v.skolekode, v.er_matrikel_hovedadresse, v.latitude, v.longitude
FROM (VALUES
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
    ('Åby Skole',                           'Åbyvej 80, 8230 Åbyhøj',                          751054, 1, 56.150634, 10.164975)
) AS v (matrikel_navn, matrikel_adresse, skolekode, er_matrikel_hovedadresse, latitude, longitude);
PRINT CONCAT('Skolematrikel: ', @@ROWCOUNT, ' row(s) inserted.');


-- Ungdomsuddannelse  (27 rows)
--
-- The comment after each row is the institution number from the source list
-- the names came from. There is no column for it — it is kept here so a row
-- can be traced back when the list is next reconciled.
--
-- Rows marked TODO need an address and coordinates filled in. They are
-- deliberately 'UDFYLD ADRESSE' and NULL rather than a plausible guess:
--   * the address is printed on the afgørelsesbrev, so a wrong one is worse
--     than an obviously missing one;
--   * NULL coordinates make the distance calculation report "ingen
--     koordinater" instead of silently measuring to the wrong place.
-- The column is NOT NULL, hence a marker string rather than NULL there.
INSERT INTO [befordring].[Ungdomsuddannelse] (ungdomsuddannelse_navn, ungdomsuddannelse_adresse, latitude, longitude)
SELECT v.ungdomsuddannelse_navn, v.ungdomsuddannelse_adresse, v.latitude, v.longitude
FROM (VALUES
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
    ('AARHUS TECH, Aarhus N',                             'Halmstadgade 6, 8200 Aarhus N',          56.184376, 10.191661)
) AS v (ungdomsuddannelse_navn, ungdomsuddannelse_adresse, latitude, longitude);
PRINT CONCAT('Ungdomsuddannelse: ', @@ROWCOUNT, ' row(s) inserted.');


-- Hjaelpemiddel  (7 rows)
INSERT INTO [befordring].[Hjaelpemiddel] (hjaelpemiddel_tekst, beskrivelse, aktiv)
SELECT v.hjaelpemiddel_tekst, v.beskrivelse, v.aktiv
FROM (VALUES
    ('Magnetsele',  '', 1),
    ('Selekappe',   '', 1),
    ('Krampeplan',  '', 1),
    ('Kørestol',    '', 1),
    ('Krykker',     '', 1),
    ('Autostol',    '', 1),
    ('El-kørestol', '', 1)
) AS v (hjaelpemiddel_tekst, beskrivelse, aktiv);
PRINT CONCAT('Hjaelpemiddel: ', @@ROWCOUNT, ' row(s) inserted.');


-- Hjemmel  (8 rows)
INSERT INTO [befordring].[Hjemmel] (hjemmel_tekst, beskrivelse, aktiv)
SELECT v.hjemmel_tekst, v.beskrivelse, v.aktiv
FROM (VALUES
    ('§ 26, stk. 1 afstand',               '', 1),
    ('§ 26, stk. 2 sygdom',                '', 1),
    ('§ 26, stk. 1 og 2',                  '', 1),
    ('§ 33, stk. 3 (ungdomsskolen)',	   '', 1),
    ('§ 36, stk. 3 frit skolevalg',		   '', 1),
    ('§ 36, stk. 4 retten til at forblive','', 1),
    ('§ 9,  stk. 4 UngiAarhus',            '', 1),
    ('§ 10 (brækket ben)',				   '', 1)
) AS v (hjemmel_tekst, beskrivelse, aktiv);
PRINT CONCAT('Hjemmel: ', @@ROWCOUNT, ' row(s) inserted.');


-- Afgoerelsesbrev  (22 rows)
INSERT INTO [befordring].[Afgoerelsesbrev] (afgoerelsesbrev_tekst, beskrivelse, aktiv)
SELECT v.afgoerelsesbrev_tekst, v.beskrivelse, v.aktiv
FROM (VALUES
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
    ('Ophør: § 26, stk. 1, nr. 1 (afstand)',                                    '', 1),
    ('Ophør: § 26, stk. 1, nr. 2 (farlig skolevej)',                             '', 1),
    ('Påtænkt afslag: § 26, stk. 1, nr. 2 (farlig skolevej)',                    '', 1),
    ('Påtænkt afslag: § 26, stk. 2 (sygdom)',                                    '', 1),
    ('Påtænkt afslag: § 26, stk. 2, § 36, stk. 4 (retten til at forblive)',      '', 1),
    ('Påtænkt bevilling: § 26, stk. 1 (afstand)',                                '', 1),
    ('Påtænkt bevilling: § 26, stk. 2 (sygdom)',                                 '', 1),
    ('Påtænkt ophør: § 26, stk. 2 (sygdom)',                                     '', 1),
    ('Midlertidig kørsel bevilling: § 26, stk. 2 (brækket ben folkeskole)',      '', 1),
    ('Midlertidig kørsel afslag: § 26, stk. 2 (brækket ben folkeskole)',         '', 1),
    ('Midlertidig kørsel bevilling: § 10 (brækket ben ungdomssuddannelse)',      '', 1),
    ('Midlertidig kørsel afslag: § 10 (brækket ben ungdomssuddannelse)',         '', 1)
) AS v (afgoerelsesbrev_tekst, beskrivelse, aktiv);
PRINT CONCAT('Afgoerelsesbrev: ', @@ROWCOUNT, ' row(s) inserted.');


-- KoerselstypeTillaeg  (4 rows)
INSERT INTO [befordring].[KoerselstypeTillaeg] (tillaeg_tekst, beskrivelse, aktiv)
SELECT v.tillaeg_tekst, v.beskrivelse, v.aktiv
FROM (VALUES
    ('Fast forsæde',  '', 1),
    ('Co-driver',     '', 1),
    ('Egen ledsager', '', 1),
    ('Fast sæde',     '', 1)
) AS v (tillaeg_tekst, beskrivelse, aktiv);
PRINT CONCAT('KoerselstypeTillaeg: ', @@ROWCOUNT, ' row(s) inserted.');


-- Befordringstype  (9 rows)
INSERT INTO [befordring].[Befordringstype] (befordringstype_tekst, beskrivelse, aktiv)
SELECT v.befordringstype_tekst, v.beskrivelse, v.aktiv
FROM (VALUES
    ('Rutekørsel',                       '', 1),
    ('Skånekørsel',                      '', 1),
    ('Solokørsel',                       '', 1),
    ('Variabel kørsel',                  '', 1),
    ('Skolerejsekort',                   '', 1),
    ('Skolebus',                         '', 1),
    ('Egen befordring',                  '', 1),
    ('Cykelbus',                         '', 1),
    ('Gåbus',                            '', 1)
) AS v (befordringstype_tekst, beskrivelse, aktiv);
PRINT CONCAT('Befordringstype: ', @@ROWCOUNT, ' row(s) inserted.');


-- Tidspunkt  (3 rows)
INSERT INTO [befordring].[Tidspunkt] (tidspunkt_tekst, beskrivelse, aktiv)
SELECT v.tidspunkt_tekst, v.beskrivelse, v.aktiv
FROM (VALUES
    ('Morgen',                '', 1),
    ('Eftermiddag',           '', 1),
    ('Morgen og eftermiddag', '', 1)
) AS v (tidspunkt_tekst, beskrivelse, aktiv);
PRINT CONCAT('Tidspunkt: ', @@ROWCOUNT, ' row(s) inserted.');


-- Rutetype  (6 rows)
INSERT INTO [befordring].[Rutetype] (rutetype_tekst, beskrivelse, aktiv, sorteringsorden)
SELECT v.rutetype_tekst, v.beskrivelse, v.aktiv, v.sorteringsorden
FROM (VALUES
    -- Rækkefølgen er Befordrings, og den er IKKE den samme som den, de
    -- listede typerne i. Derfor en kolonne og ikke en liste i koden; den
    -- læses af både kørselsrækkesorteringen og brevet. Se migration 032.
    ('Mellem hjem og skole',        '', 1, 1),
    ('Mellem skole, klub, og hjem', '', 1, 2),
    ('Fra hjem til skole',          '', 1, 3),
    ('Fra skole til klub',          '', 1, 4),
    ('Fra skole til hjem',          '', 1, 5),
    ('Fra klub til hjem',           '', 1, 6)
) AS v (rutetype_tekst, beskrivelse, aktiv, sorteringsorden);
PRINT CONCAT('Rutetype: ', @@ROWCOUNT, ' row(s) inserted.');


-- SagsaktivitetType  (15 rows)
--
-- The event kinds the Sagsforløb feed knows. Written by the application as
-- type_kode on every Sagsaktivitet row; the frontend styles and groups on the
-- code rather than on the Danish text, so renaming a label no longer changes
-- how the feed behaves.
--
-- Created and first seeded by migration 023 (plus 024 and 025). Listed here
-- as well, because this file is the definition of what the lookups contain —
-- a fresh database seeded from it must end up with the same set.
INSERT INTO [befordring].[SagsaktivitetType] (type_kode)
SELECT v.type_kode
FROM (VALUES
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
    (N'status_opdateret')
) AS v (type_kode);
PRINT CONCAT('SagsaktivitetType: ', @@ROWCOUNT, ' row(s) inserted.');


-- Ugedag  (6 rows)
INSERT INTO [befordring].[Ugedag] (dag_tekst, beskrivelse, aktiv)
SELECT v.dag_tekst, v.beskrivelse, v.aktiv
FROM (VALUES
    ('Mandag',  NULL,            1),
    ('Tirsdag', NULL,            1),
    ('Onsdag',  NULL,            1),
    ('Torsdag', NULL,            1),
    ('Fredag',  NULL,            1),
    ('Alle',    'Alle hverdage', 1)
) AS v (dag_tekst, beskrivelse, aktiv);
PRINT CONCAT('Ugedag: ', @@ROWCOUNT, ' row(s) inserted.');


/* ============================================================
   Verify — row counts per lookup table
============================================================ */

SELECT 'Status'              AS lookup_table, COUNT(*) AS antal_rows FROM [befordring].[Status]
-- Not seeded here (see the header), but counted: an empty Sagsbehandler table
-- is a working database that the conversion bot cannot run against.
UNION ALL SELECT 'Sagsbehandler *',     COUNT(*) FROM [befordring].[Sagsbehandler]
UNION ALL SELECT 'PPR_Sagsbehandler *', COUNT(*) FROM [befordring].[PPR_Sagsbehandler]
UNION ALL SELECT 'Skolematrikel',       COUNT(*) FROM [befordring].[Skolematrikel]
UNION ALL SELECT 'Ungdomsuddannelse',   COUNT(*) FROM [befordring].[Ungdomsuddannelse]
UNION ALL SELECT 'Hjaelpemiddel',       COUNT(*) FROM [befordring].[Hjaelpemiddel]
UNION ALL SELECT 'Hjemmel',             COUNT(*) FROM [befordring].[Hjemmel]
UNION ALL SELECT 'Afgoerelsesbrev',     COUNT(*) FROM [befordring].[Afgoerelsesbrev]
UNION ALL SELECT 'KoerselstypeTillaeg', COUNT(*) FROM [befordring].[KoerselstypeTillaeg]
UNION ALL SELECT 'Befordringstype',     COUNT(*) FROM [befordring].[Befordringstype]
UNION ALL SELECT 'Tidspunkt',           COUNT(*) FROM [befordring].[Tidspunkt]
UNION ALL SELECT 'SagsaktivitetType',   COUNT(*) FROM [befordring].[SagsaktivitetType]
UNION ALL SELECT 'Rutetype',            COUNT(*) FROM [befordring].[Rutetype]
UNION ALL SELECT 'Ugedag',              COUNT(*) FROM [befordring].[Ugedag]
ORDER BY lookup_table;


/* ============================================================
   Safety check — duplicate natural keys

   Should return NO rows. Anything here means a lookup table holds two rows
   with the same human-meaningful value, which makes the dropdowns ambiguous
   and means some bevilling is pointing at one of them arbitrarily. This
   script cannot create such a row, but it will surface one that already
   exists (for example from an older non-guarded seed run).
============================================================ */

SELECT 'Status' AS lookup_table, LTRIM(RTRIM(status_tekst)) AS value, COUNT(*) AS antal
FROM [befordring].[Status] GROUP BY LTRIM(RTRIM(status_tekst)) HAVING COUNT(*) > 1
UNION ALL SELECT 'Sagsbehandler *',     LTRIM(RTRIM(sagsbehandler_tekst)),     COUNT(*) FROM [befordring].[Sagsbehandler]       GROUP BY LTRIM(RTRIM(sagsbehandler_tekst))     HAVING COUNT(*) > 1
UNION ALL SELECT 'PPR_Sagsbehandler *', LTRIM(RTRIM(ppr_sagsbehandler_tekst)), COUNT(*) FROM [befordring].[PPR_Sagsbehandler]   GROUP BY LTRIM(RTRIM(ppr_sagsbehandler_tekst)) HAVING COUNT(*) > 1
UNION ALL SELECT 'Skolematrikel',       LTRIM(RTRIM(matrikel_navn)),           COUNT(*) FROM [befordring].[Skolematrikel]       GROUP BY LTRIM(RTRIM(matrikel_navn))           HAVING COUNT(*) > 1
UNION ALL SELECT 'Ungdomsuddannelse',   LTRIM(RTRIM(ungdomsuddannelse_navn)),  COUNT(*) FROM [befordring].[Ungdomsuddannelse]   GROUP BY LTRIM(RTRIM(ungdomsuddannelse_navn))  HAVING COUNT(*) > 1
UNION ALL SELECT 'Hjaelpemiddel',       LTRIM(RTRIM(hjaelpemiddel_tekst)),     COUNT(*) FROM [befordring].[Hjaelpemiddel]       GROUP BY LTRIM(RTRIM(hjaelpemiddel_tekst))     HAVING COUNT(*) > 1
UNION ALL SELECT 'Hjemmel',             LTRIM(RTRIM(hjemmel_tekst)),           COUNT(*) FROM [befordring].[Hjemmel]             GROUP BY LTRIM(RTRIM(hjemmel_tekst))           HAVING COUNT(*) > 1
UNION ALL SELECT 'Afgoerelsesbrev',     LTRIM(RTRIM(afgoerelsesbrev_tekst)),   COUNT(*) FROM [befordring].[Afgoerelsesbrev]     GROUP BY LTRIM(RTRIM(afgoerelsesbrev_tekst))   HAVING COUNT(*) > 1
UNION ALL SELECT 'KoerselstypeTillaeg', LTRIM(RTRIM(tillaeg_tekst)),           COUNT(*) FROM [befordring].[KoerselstypeTillaeg] GROUP BY LTRIM(RTRIM(tillaeg_tekst))           HAVING COUNT(*) > 1
UNION ALL SELECT 'Befordringstype',     LTRIM(RTRIM(befordringstype_tekst)),   COUNT(*) FROM [befordring].[Befordringstype]     GROUP BY LTRIM(RTRIM(befordringstype_tekst))   HAVING COUNT(*) > 1
UNION ALL SELECT 'Tidspunkt',           LTRIM(RTRIM(tidspunkt_tekst)),         COUNT(*) FROM [befordring].[Tidspunkt]           GROUP BY LTRIM(RTRIM(tidspunkt_tekst))         HAVING COUNT(*) > 1
UNION ALL SELECT 'SagsaktivitetType',   LTRIM(RTRIM(type_kode)),               COUNT(*) FROM [befordring].[SagsaktivitetType] GROUP BY LTRIM(RTRIM(type_kode))               HAVING COUNT(*) > 1
UNION ALL SELECT 'Rutetype',            LTRIM(RTRIM(rutetype_tekst)),          COUNT(*) FROM [befordring].[Rutetype]            GROUP BY LTRIM(RTRIM(rutetype_tekst))          HAVING COUNT(*) > 1
UNION ALL SELECT 'Ugedag',              LTRIM(RTRIM(dag_tekst)),               COUNT(*) FROM [befordring].[Ugedag]              GROUP BY LTRIM(RTRIM(dag_tekst))               HAVING COUNT(*) > 1;

PRINT '';
PRINT 'ROLLBACK is active. Change to COMMIT when the counts look correct.';
PRINT '';

ROLLBACK TRANSACTION;


/* ============================================================
   Put the identity counters back in step with the rows

   DBCC CHECKIDENT is NOT transactional. The RESEED, 0 above therefore
   survives whichever way the transaction above ended, and the two cases need
   opposite things:

     COMMIT   — the tables hold exactly the rows seeded here, numbered from
                1, and the counters already match. This is a no-op.
     ROLLBACK — the rows are back as they were, but the counters are at 0, so
                the next insert into any of these tables would collide with
                an existing id. This is the repair that matters.

   Setting each counter to the table's current MAX is right in both cases, and
   needs no knowledge of which one happened. An empty table gets 0, so its
   first insert is 1.

   This runs OUTSIDE the transaction deliberately. Do not move it above the
   ROLLBACK/COMMIT.
============================================================ */

DECLARE @naeste BIGINT;

SET @naeste = (SELECT ISNULL(MAX([afgoerelsesbrev_id]), 0) FROM [befordring].[Afgoerelsesbrev]);
DBCC CHECKIDENT ('[befordring].[Afgoerelsesbrev]', RESEED, @naeste);

SET @naeste = (SELECT ISNULL(MAX([befordringstype_id]), 0) FROM [befordring].[Befordringstype]);
DBCC CHECKIDENT ('[befordring].[Befordringstype]', RESEED, @naeste);

SET @naeste = (SELECT ISNULL(MAX([hjaelpemiddel_id]), 0) FROM [befordring].[Hjaelpemiddel]);
DBCC CHECKIDENT ('[befordring].[Hjaelpemiddel]', RESEED, @naeste);

SET @naeste = (SELECT ISNULL(MAX([hjemmel_id]), 0) FROM [befordring].[Hjemmel]);
DBCC CHECKIDENT ('[befordring].[Hjemmel]', RESEED, @naeste);

SET @naeste = (SELECT ISNULL(MAX([tillaeg_id]), 0) FROM [befordring].[KoerselstypeTillaeg]);
DBCC CHECKIDENT ('[befordring].[KoerselstypeTillaeg]', RESEED, @naeste);

SET @naeste = (SELECT ISNULL(MAX([rutetype_id]), 0) FROM [befordring].[Rutetype]);
DBCC CHECKIDENT ('[befordring].[Rutetype]', RESEED, @naeste);

SET @naeste = (SELECT ISNULL(MAX([type_id]), 0) FROM [befordring].[SagsaktivitetType]);
DBCC CHECKIDENT ('[befordring].[SagsaktivitetType]', RESEED, @naeste);

SET @naeste = (SELECT ISNULL(MAX([matrikel_id]), 0) FROM [befordring].[Skolematrikel]);
DBCC CHECKIDENT ('[befordring].[Skolematrikel]', RESEED, @naeste);

SET @naeste = (SELECT ISNULL(MAX([status_id]), 0) FROM [befordring].[Status]);
DBCC CHECKIDENT ('[befordring].[Status]', RESEED, @naeste);

SET @naeste = (SELECT ISNULL(MAX([tidspunkt_id]), 0) FROM [befordring].[Tidspunkt]);
DBCC CHECKIDENT ('[befordring].[Tidspunkt]', RESEED, @naeste);

SET @naeste = (SELECT ISNULL(MAX([dag_id]), 0) FROM [befordring].[Ugedag]);
DBCC CHECKIDENT ('[befordring].[Ugedag]', RESEED, @naeste);

SET @naeste = (SELECT ISNULL(MAX([ungdomsuddannelse_id]), 0) FROM [befordring].[Ungdomsuddannelse]);
DBCC CHECKIDENT ('[befordring].[Ungdomsuddannelse]', RESEED, @naeste);

PRINT 'Identity counters aligned with the current rows.';
