/* ============================================================
   Konverter "Til hjem" -> "Fra skole til hjem"

   Den SIDSTE af de gamle rutetyper, og den eneste der ikke kunne flyttes
   maskinelt fra starten: "Til hjem" kunne være en tur hjem fra skole
   ELLER fra klub, og de to blev til hver sin nye rutetype. Derfor blev
   den holdt tilbage, mens "Til skole" og "Til klub" blev konverteret.

   Den kan køres nu, fordi Befordring har gennemgået klub-kørslerne og
   flyttet dem selv. Det, der er tilbage under "Til hjem", er dermed
   ture hjem FRA SKOLE — og kun dem.

   FORUDSÆTNINGEN ER NETOP DET. Kører scriptet, mens der stadig ligger
   klub-ture under "Til hjem", bliver de stemplet "Fra skole til hjem",
   og derefter kan de ikke skelnes fra de rigtige. Del 1 viser rækkerne
   med kørselstype og bevilling, så de kan kontrolleres, inden der
   committes — og @antal = 1 gør, at den første tur kan ses i UI'et før
   resten.

   OMFANG: alle aktive kørselsrækker med "Til hjem", uanset bevillingens
   status. Det er en ren omdøbning af den samme rute, så den gælder også
   bagud — og bliver de gamle rækker stående, står der to navne for den
   samme ting i systemet på ubestemt tid. Vil I hellere kun rette dem,
   sagsbehandlerne ser på listen, så sæt @kun_ikke_udloebne = 1 nedenfor.

   Når denne er kørt helt igennem, er der ingen aktive rækker tilbage på
   de gamle rutetyper — del 3 er stedet at aflæse det.

   Soft-deletede rækker (aktiv = 0) røres ikke. De er historik, og de
   vises ingen steder.

   @antal styrer hvor mange rækker der rettes, og står på 1. Tag den ene
   først, kig på den i UI'et, og skru så op. Sæt @antal = NULL for resten.
   Udvælgelsen er sorteret på koersel_id, så del 1 viser PRÆCIS de rækker,
   del 2 retter — ikke et tilfældigt udsnit af de samme kandidater.

   Scriptet ROLLBACKER. Skift ROLLBACK til COMMIT nederst, når del 1 og 2
   ser rigtige ud — det er det manuelle skridt, der ændrer noget.
============================================================ */

USE [Befordringssystemet];

SET NOCOUNT ON;
SET XACT_ABORT ON;

/* Hvor mange rækker der rettes. 1 for en prøvetur, NULL for dem alle. */
DECLARE @antal int = 1;

/* Sæt til 1 for kun at rette rækker på bevillinger, der ikke er udløbet. */
DECLARE @kun_ikke_udloebne bit = 0;

DECLARE @fra_tekst nvarchar(255) = N'Til hjem';
DECLARE @til_tekst nvarchar(255) = N'Fra skole til hjem';

DECLARE @fra_id int = (SELECT TOP 1 rutetype_id FROM [befordring].[Rutetype]
                       WHERE LTRIM(RTRIM(rutetype_tekst)) = @fra_tekst ORDER BY rutetype_id);
DECLARE @til_id int = (SELECT TOP 1 rutetype_id FROM [befordring].[Rutetype]
                       WHERE LTRIM(RTRIM(rutetype_tekst)) = @til_tekst ORDER BY rutetype_id);

/* Stop hellere end at ramme forbi: mangler måltypen, er migration 032 ikke
   kørt på denne database, og en UPDATE ville sætte rutetype_id = NULL. */
IF @til_id IS NULL
BEGIN
    RAISERROR(N'"Fra skole til hjem" findes ikke i Rutetype — kør migration 032 foerst.', 16, 1);
    RETURN;
END

IF @fra_id IS NULL
BEGIN
    PRINT '"Til hjem" findes ikke i Rutetype — der er intet at konvertere.';
    RETURN;
END


BEGIN TRANSACTION;

/* ------------------------------------------------------------
   1. Hvad bliver rettet — før

   Samme TOP og samme ORDER BY som del 2, så de to ser på de samme rækker.
   Antallet af kandidater i alt står i del 3.
------------------------------------------------------------ */
SELECT TOP (ISNULL(@antal, 2147483647))
    STUFF(e.cpr, 7, 0, '-')  AS cpr,
    e.adresseringsnavn,
    b.bevilling_id,
    b.loebenummer,
    st.status_tekst          AS bevilling_status,
    k.koersel_id,
    k.gyldig_fra,
    k.gyldig_til,
    bt.befordringstype_tekst AS koerselstype,
    k.final                  AS raekke_laast
FROM       [befordring].[Koersel]          k
INNER JOIN [befordring].[Bevilling]        b  ON b.bevilling_id = k.bevilling_id AND b.aktiv = 1
INNER JOIN [befordring].[Elev]             e  ON e.cpr          = b.cpr_elev
INNER JOIN [befordring].[Status]           st ON st.status_id   = b.status_id
LEFT  JOIN [befordring].[Befordringstype]  bt ON bt.befordringstype_id = k.befordringstype_id
WHERE  k.aktiv       = 1
  AND  k.rutetype_id = @fra_id
  AND  (@kun_ikke_udloebne = 0 OR st.status_tekst <> N'Udløbet')
ORDER BY k.koersel_id;


/* ------------------------------------------------------------
   2. Rettelsen

   Bevidst UDEN hensyn til k.final: en låst kørselsrække er låst mod
   sagsbehandling, ikke mod en omdøbning af den rute, den allerede
   beskriver. Indholdet er det samme bagefter.
------------------------------------------------------------ */
WITH maal AS (
    SELECT TOP (ISNULL(@antal, 2147483647))
           k.rutetype_id
    FROM       [befordring].[Koersel]   k
    INNER JOIN [befordring].[Bevilling] b  ON b.bevilling_id = k.bevilling_id AND b.aktiv = 1
    INNER JOIN [befordring].[Status]    st ON st.status_id   = b.status_id
    WHERE  k.aktiv       = 1
      AND  k.rutetype_id = @fra_id
      AND  (@kun_ikke_udloebne = 0 OR st.status_tekst <> N'Udløbet')
    -- Samme sortering som del 1. Uden den ville TOP tage en vilkårlig
    -- delmængde, og forhåndsvisningen ville vise andre rækker end dem,
    -- der blev rettet.
    ORDER BY k.koersel_id
)
UPDATE maal
SET    rutetype_id = @til_id;

PRINT CONCAT('Koersel: ', @@ROWCOUNT, ' raekke(r) flyttet til "Fra skole til hjem".');


/* ------------------------------------------------------------
   3. Hvad står tilbage på gamle rutetyper

   Med @antal = 1 står "Til hjem" stadig med resten — det er meningen.
   Tallet her er, hvad der er tilbage at køre igennem.

   Står der 0 aktive rækker på ALLE de gamle rutetyper, er konverteringen
   færdig, og de gamle typer kan deaktiveres.
------------------------------------------------------------ */
SELECT
    r.rutetype_tekst,
    r.aktiv,
    r.sorteringsorden,
    COUNT(k.koersel_id) AS aktive_raekker
FROM       [befordring].[Rutetype] r
LEFT  JOIN [befordring].[Koersel]  k  ON k.rutetype_id = r.rutetype_id AND k.aktiv = 1
LEFT  JOIN [befordring].[Bevilling] b ON b.bevilling_id = k.bevilling_id AND b.aktiv = 1
GROUP BY r.rutetype_tekst, r.aktiv, r.sorteringsorden
ORDER BY CASE WHEN r.sorteringsorden IS NULL THEN 1 ELSE 0 END,
         r.sorteringsorden,
         r.rutetype_tekst;


PRINT '';
PRINT 'ROLLBACK er aktiv — intet er aendret. Skift til COMMIT for at gennemfoere.';
PRINT '';

ROLLBACK TRANSACTION;
