/* ============================================================
   Konverter de SIDSTE rækker på de gamle rutetyper

   Efter konverteringen af de aktive rækker står der kun soft-slettede
   tilbage:

       Til hjem   13 rækker   -> Fra skole til hjem
       Til skole   3 rækker   -> Fra hjem til skole
       Til klub    1 række    -> Fra skole til klub

   Alle med aktiv = 0. De vises ingen steder i UI'et, men de holder en
   fremmednøgle på Koersel.rutetype_id, og derfor kan de gamle rutetyper
   ikke slettes, så længe de peger på dem. Derfor flyttes de med.

   "Til hjem" er den samme antagelse som for de aktive rækker: det der er
   tilbage, er ture hjem FRA SKOLE. Her vejer den lettere — rækkerne er
   slettede og indgår hverken i breve, udbetaling eller visning. Formålet
   er at frigøre nøglen, ikke at genfortolke historik.

   AFVIGER FRA de to andre konverteringsscripts ved IKKE at filtrere på
   k.aktiv: her er det netop de slettede rækker, der er tilbage.

   @slet_gamle_typer = 1 sletter desuden de gamle rutetyper til sidst —
   men kun dem, der efter konverteringen har NUL rækker overhovedet.
   Står den på 0, konverteres der kun, og del 3 viser om de er klar.

   Scriptet ROLLBACKER. Skift ROLLBACK til COMMIT nederst, når del 1-3
   ser rigtige ud — det er det manuelle skridt, der ændrer noget.
============================================================ */

USE [Befordringssystemet];

SET NOCOUNT ON;
SET XACT_ABORT ON;

/* Sæt til 1 for også at slette de gamle rutetyper, når de er tomme. */
DECLARE @slet_gamle_typer bit = 0;


/* Kortet over konverteringen. Teksterne slås op frem for at skrive id'er,
   så scriptet kan køres på en hvilken som helst database — id'erne er
   autoincrements og er ikke de samme i dev og prod. */
DECLARE @map TABLE (fra_tekst nvarchar(255), til_tekst nvarchar(255));

INSERT INTO @map (fra_tekst, til_tekst) VALUES
    (N'Til hjem',  N'Fra skole til hjem'),
    (N'Til skole', N'Fra hjem til skole'),
    (N'Til klub',  N'Fra skole til klub');


/* Stop hellere end at ramme forbi: mangler en måltype, er migration 032
   ikke kørt her, og en UPDATE ville sætte rutetype_id til NULL. */
IF EXISTS (
    SELECT 1 FROM @map m
    WHERE NOT EXISTS (SELECT 1 FROM [befordring].[Rutetype] r
                      WHERE LTRIM(RTRIM(r.rutetype_tekst)) = m.til_tekst)
)
BEGIN
    RAISERROR(N'En eller flere maaltyper findes ikke i Rutetype — koer migration 032 foerst.', 16, 1);
    RETURN;
END

/* Og mere end én række med samme navn ville gøre UPDATE'en nedenfor
   vilkårlig: SQL Server fejler ikke på flere match i et UPDATE ... FROM,
   den vælger bare et af dem. */
IF EXISTS (
    SELECT 1 FROM @map m
    JOIN   [befordring].[Rutetype] r ON LTRIM(RTRIM(r.rutetype_tekst)) = m.til_tekst
    GROUP BY m.til_tekst
    HAVING COUNT(*) > 1
)
BEGIN
    RAISERROR(N'Mindst en maaltype findes flere gange i Rutetype — ryd op foerst.', 16, 1);
    RETURN;
END


BEGIN TRANSACTION;

/* ------------------------------------------------------------
   1. Hvad bliver rettet — før

   Alle rækkerne, ikke et udsnit: der er under 20 i alt, så de kan
   gennemses i deres helhed.
------------------------------------------------------------ */
SELECT
    k.koersel_id,
    k.aktiv                  AS raekke_ikke_slettet,
    r_fra.rutetype_tekst     AS fra_rutetype,
    m.til_tekst              AS til_rutetype,
    b.bevilling_id,
    b.aktiv                  AS bevilling_ikke_slettet,
    st.status_tekst          AS bevilling_status,
    STUFF(b.cpr_elev, 7, 0, '-') AS cpr,
    k.gyldig_fra,
    k.gyldig_til,
    bt.befordringstype_tekst AS koerselstype
FROM       [befordring].[Koersel]          k
INNER JOIN [befordring].[Rutetype]         r_fra ON r_fra.rutetype_id = k.rutetype_id
INNER JOIN @map                            m     ON m.fra_tekst = LTRIM(RTRIM(r_fra.rutetype_tekst))
INNER JOIN [befordring].[Bevilling]        b     ON b.bevilling_id = k.bevilling_id
LEFT  JOIN [befordring].[Status]           st    ON st.status_id = b.status_id
LEFT  JOIN [befordring].[Befordringstype]  bt    ON bt.befordringstype_id = k.befordringstype_id
ORDER BY r_fra.rutetype_tekst, k.koersel_id;


/* ------------------------------------------------------------
   2. Rettelsen

   Uden filter på k.aktiv og uden hensyn til k.final: en slettet eller
   låst række er stadig den samme rute, og omdøbningen ændrer intet
   indhold.
------------------------------------------------------------ */
UPDATE k
SET    k.rutetype_id = r_til.rutetype_id
FROM       [befordring].[Koersel]  k
INNER JOIN [befordring].[Rutetype] r_fra ON r_fra.rutetype_id = k.rutetype_id
INNER JOIN @map                    m     ON m.fra_tekst = LTRIM(RTRIM(r_fra.rutetype_tekst))
INNER JOIN [befordring].[Rutetype] r_til ON LTRIM(RTRIM(r_til.rutetype_tekst)) = m.til_tekst;

PRINT CONCAT('Koersel: ', @@ROWCOUNT, ' raekke(r) flyttet til de nye rutetyper.');


/* ------------------------------------------------------------
   3. Status pr. rutetype efter rettelsen

   raekker_i_alt tæller ALT — også slettede rækker. Det er det tal, der
   afgør, om en rutetype kan slettes: fremmednøglen skelner ikke.
------------------------------------------------------------ */
SELECT
    r.rutetype_id,
    r.rutetype_tekst,
    r.aktiv,
    r.sorteringsorden,
    (SELECT COUNT(*) FROM [befordring].[Koersel] k
     WHERE k.rutetype_id = r.rutetype_id)                 AS raekker_i_alt,
    (SELECT COUNT(*) FROM [befordring].[Koersel] k
     WHERE k.rutetype_id = r.rutetype_id AND k.aktiv = 1) AS aktive
FROM   [befordring].[Rutetype] r
ORDER BY CASE WHEN r.sorteringsorden IS NULL THEN 1 ELSE 0 END,
         r.sorteringsorden,
         r.rutetype_tekst;


/* ------------------------------------------------------------
   4. Slet de gamle rutetyper — kun hvis @slet_gamle_typer = 1

   Betingelsen er NUL rækker overhovedet, ikke nul aktive. En rutetype
   med en enkelt slettet række tilbage bliver stående, og del 3 viser
   hvilken.

   sorteringsorden IS NULL er kendetegnet for de gamle typer: migration
   032 gav alle seks nye en orden, og kun dem.
------------------------------------------------------------ */
IF @slet_gamle_typer = 1
BEGIN
    DELETE r
    FROM   [befordring].[Rutetype] r
    WHERE  r.sorteringsorden IS NULL
    AND    NOT EXISTS (SELECT 1 FROM [befordring].[Koersel] k
                       WHERE k.rutetype_id = r.rutetype_id);

    PRINT CONCAT('Rutetype: ', @@ROWCOUNT, ' gammel type slettet.');
END
ELSE
BEGIN
    PRINT 'Sletning sprunget over (@slet_gamle_typer = 0).';
END


PRINT '';
PRINT 'ROLLBACK er aktiv — intet er aendret. Skift til COMMIT for at gennemfoere.';
PRINT '';

ROLLBACK TRANSACTION;
