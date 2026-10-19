  <script lang="ts">
    import { onMount, createEventDispatcher } from "svelte";
    import { backendFetch } from "$lib/client/backendFetch";
    import { filterHjemler, filterAfgoerelsesbreve, filterAfgoerelsesbreveByStatus, isMidlertidigKoersel } from "$lib/lookupFilters";
    import { MIN_DATE, MAX_DATE, isDateOutOfRange, iDagISO } from "$lib/dates";
    import {
      AFSTANDSKRITERIE_KLASSETRIN,
      beregnAfstandskriterieDato,
      beregnAfstandskriterieKlassetrin
    } from "$lib/afstandskriterie";
    import AddresseSearch from "$lib/components/AddresseSearch.svelte";
    import DagePicker from "$lib/components/DagePicker.svelte";
    import {
      availableKoerselstyper as koerselstyperFor,
      isEgenbefordring as typeIsEgenbefordring,
      isSkolerejsekort as typeIsSkolerejsekort,
      isTaxaType as typeIsTaxa,
    } from "$lib/koerselstype";
    import { afstandFraKoordinater, gaaafstandForPar } from "$lib/client/afstand";
    import { harEftermiddagForRutetype } from "$lib/rutetype";
    import { primaerBevilling } from "$lib/statusRang";
    import { bevillingLabel } from "$lib/bevillingLabel";
    import { vaelgGaeldendeBevilling } from "$lib/bevillingRanking";

  import { ansoegerRelationOptions } from "$lib/ansoegerRelation";
    export let cpr: string;
    export let mode: 'kopi' | 'tom';
    export let existingBevillinger: any[] = [];
    export let lookupOptions: any = {};

    // The student's current klassetrin (Elev.elevklassetrin), used to derive the
    // afstandskriterie fields. Optional: without it the two fields simply stay
    // manual, which is what an ungdomsuddannelse student needs anyway.
    export let elevklassetrin: string | number | null = null;

    // Parties on the case — the egenbefordring kørselsrække names one of them
    // as the recipient of the kilometre reimbursement.
    export let parter: any[] = [];

    // Set when the form is the whole page rather than a modal over one — the
    // separate "opret bevilling" window. There is nothing behind it to dim and
    // nothing to centre it in, so the backdrop and the fixed width only take
    // room away from the form.
    export let standalone = false;

    const dispatch = createEventDispatcher<{ created: void; cancel: void }>();

    function emptyToNull(value: any) { return value === "" ? null : value; }
    function numberOrNull(value: any) { return value === "" ? null : Number(value); }
    

    function validateBevillingDates(): boolean {
      const fields: [string, string][] = [
        [newBevilling.revurderingsdato,      'Revurderingsdato'],
        [newBevilling.befordringsudvalg,     'Befordringsudvalg'], 
        [newBevilling.sagsbehandlingsdato,   'Sagsbehandlingsdato'],
        [newBevilling.foerste_koersel_dato,  'Dato for første kørsel'],
        [newBevilling.afstandskriterie_dato, 'Afstandskriterie dato'],
      ];
      for (const [value, label] of fields) {
        if (isDateOutOfRange(value)) {
          modalError = `${label}: Dato er ugyldig — kontrollér årstallet`;
          return false;
        }
      }
      return true;
    }

  
  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

    let createBevillingStep: 1 | 2 = 1;
    // One entry per kørselsrække being created. Step 2 used to build exactly
    // one; a caseworker can now add several in the same pass, so the per-row
    // state (tillæg, dage, the select values, the distance lookup) moves onto
    // each entry instead of sitting in module-level variables.
    let modalKoerselList: any[] = [];
    let isCreatingKoerselInModal = false;
    let isCalculatingModalKoerselDistance = false;
    let modalError: string | null = null;
    let skoleType: 'folkeskole' | 'ungdomsuddannelse' | null = null;
    let newBevilling: any = {};
    let selectedSourceBevillingId: number | null = null;

    // Kommentar is a textarea, not an input: "Kopiér" seeds it from an
    // existing kørselsrække, whose comment may be multi-line — the conversion
    // writes such notes onto rows it could not fully interpret. A text input
    // strips CR/LF from its value, so copying one would silently flatten it.
    const kommentarClass =
      "border border-gray-300 px-2 py-1.5 text-sm rounded w-full focus:border-blue-400 focus:ring-0 leading-snug resize-y";

    $: koerselstyper       = lookupOptions.koerselstyper       ?? [];
    $: tidspunkter         = lookupOptions.tidspunkter         ?? [];
    $: koerselstypeTillaeg = lookupOptions.koerselstypeTillaeg ?? [];
    $: dage                = lookupOptions.dage                ?? [];


    // Midlertidig kørsel is granted on a different basis, so the afstandskriterie
    // fields, befordringsudvalg and PPR ansvarlig do not apply and are hidden.
    $: isMidlertidig = isMidlertidigKoersel(newBevilling.ansoegningstype);

    // "Kørsel til institution" only applies to a kørsel with an afternoon leg:
    // a morning journey goes home -> school, and the SFO or klub is where the
    // child goes afterwards.
    //
    // Answered from the RUTETYPE, not from tidspunkt. Rutetype states where a
    // trip starts and ends, so the legs follow from it, and it is the column
    // that will survive — tidspunkt is being retired. The field is still shown
    // on the form, but nothing decides anything from it any more; two sources
    // for one answer is two rules that can disagree.
    const harEftermiddagsTur = (rutetypeId: string | number | null | undefined) =>
      harEftermiddagForRutetype(lookupOptions.rutetyper, rutetypeId);

    $: availableModalKoerselstyper = koerselstyperFor(
      koerselstyper,
      newBevilling.ansoegningstype
    );

    // Resolved against the FULL list, not visibleHjemler, which is what it
    // feeds — a bevilling created "fra kopi" carries the source's hjemmel, and
    // deriving the label from the filtered list would make it disappear from
    // its own keep-alive.
    $: valgtHjemmelLabel = (lookupOptions?.hjemler ?? []).find(
      (h: any) => String(h.id) === String(newBevilling.hjemmel_id)
    )?.label ?? null;

    // null status: this modal never sets one — create_bevilling is called with
    // status_text=Kommende, which is a calculated status, so the auto-status
    // rules are the right ones.
    $: visibleHjemler = filterHjemler(
      lookupOptions?.hjemler,
      newBevilling.ansoegningstype,
      skoleType,
      null,
      valgtHjemmelLabel
    );
    $: selectedHjemmelLabel = visibleHjemler.find((h: any) => String(h.id) === String(newBevilling.hjemmel_id))?.label ?? null;
    // Same two-step the bevillingskortet uses: hjemmel narrows WHICH paragraph
    // the letter decides under, status narrows whether it decides a grant, a
    // refusal or an ophør. Without the second step this dropdown offered the
    // afslag letters on a bevilling being granted — "Midlertidig kørsel
    // afslag: …" sat right under its bevilling counterpart.
    //
    // null status: this modal never sets one. create_bevilling is called with
    // status_text=Kommende, a calculated status, so "bevilling" is the right
    // category.
    $: valgtAfgoerelsesbrevLabel = (lookupOptions?.afgoerelsesbreve ?? []).find(
      (b: any) => String(b.id) === String(newBevilling.afgoerelsesbrev_id)
    )?.label ?? null;

    $: visibleAfgoerelsesbreve = filterAfgoerelsesbreveByStatus(
      filterAfgoerelsesbreve(
        lookupOptions?.afgoerelsesbreve,
        newBevilling.ansoegningstype,
        skoleType,
        selectedHjemmelLabel
      ),
      null,
      valgtAfgoerelsesbrevLabel
    );

  // ---------------------------------------------------------------------------
  // Functions
  // ---------------------------------------------------------------------------

    // A bevilling being copied can hold a klassetrin outside the standard list,
    // and a <select> whose value matches no option silently blanks itself —
    // which looks exactly like the copy having dropped the field. Append the
    // stored value instead.
    function klassetrinOptions(current: string | number | null | undefined): string[] {
      const value = String(current ?? "").trim();
      const known = AFSTANDSKRITERIE_KLASSETRIN.map(String);

      if (!value || known.includes(value)) {
        return known;
      }

      return [...known, value];
    }

    // Walking distance for the address and school CHOSEN IN THIS FORM, which
    // is what the two derived fields below are measured against.
    //
    // Deliberately NOT Elev.skoleafstand, which the callers used to pass:
    // that measures the student's
    // current folkeregisteradresse against the school their current data
    // resolves to. A new bevilling is very often for a different pair — a
    // move, a referral — and deriving the criterion from the student's
    // current situation answered a question nobody asked. The backend stores
    // this same number on the bevilling, measured the same way, so the
    // suggestion and the stored value cannot drift apart.
    let bevillingGaaafstand: number | null = null;
    let sidsteAfstandsPar = "";

    $: opdaterGaaafstand(
        newBevilling.adresse_id,
        newBevilling.matrikel_id,
        newBevilling.ungdomsuddannelse_id,
    );

    async function opdaterGaaafstand(
        adresseId: string | null,
        matrikelId: number | string | null,
        ungdomsuddannelseId: number | string | null,
    ) {
        const par = `${adresseId ?? ""}|${matrikelId ?? ""}|${ungdomsuddannelseId ?? ""}`;

        if (par === sidsteAfstandsPar) return;

        sidsteAfstandsPar = par;

        const km = await gaaafstandForPar(adresseId, matrikelId, ungdomsuddannelseId);

        // Guard against a slower earlier request landing after a newer one:
        // the address combobox and the school select can both move before the
        // first answer returns.
        if (par === sidsteAfstandsPar) bevillingGaaafstand = km;
    }

    // Derived from the student's klassetrin and this bevilling's distance
    // rather than typed in. Recomputed whenever either changes, but not
    // written straight into newBevilling: applyBeregnetAfstandskriterie()
    // does that, so a caseworker who overrides either field keeps their value.
    $: beregnetKlassetrin = beregnAfstandskriterieKlassetrin(elevklassetrin, bevillingGaaafstand);
    $: beregnetDato = beregnAfstandskriterieDato(elevklassetrin, bevillingGaaafstand);

    function applyBeregnetAfstandskriterie() {
      if (beregnetKlassetrin === null || beregnetDato === null) {
        return;
      }

      newBevilling = {
        ...newBevilling,
        afstandskriterie_klassetrin: String(beregnetKlassetrin),
        afstandskriterie_dato: beregnetDato
      };
    }

    function resetLookupSelections() {
      newBevilling = { ...newBevilling, hjemmel_id: "", afgoerelsesbrev_id: "" };
    }

    function onAnsoegningstypeChange() {
      resetLookupSelections();

      // Drop anything already typed into the fields that are about to be
      // hidden, so a value entered under another ansøgningstype cannot be
      // submitted invisibly. Only on the way *into* Midlertidig — switching
      // between two other types must not discard the user's input.
      if (isMidlertidigKoersel(newBevilling.ansoegningstype)) {
        newBevilling = {
          ...newBevilling,
          afstandskriterie_dato: "",
          afstandskriterie_klassetrin: "",
          befordringsudvalg: "",
          ppr_sagsbehandler_id: ""
        };
      }
    }

    function getEmptyBevilling() {
      return {
        adresse_id: null as string | null,
        adresse_tekst: "",
        // Carried alongside the id so the distance can be calculated without
        // geocoding the text back into the coordinates we were just handed.
        adresse_lat: null as number | null,
        adresse_lon: null as number | null,
        matrikel_id: "",
        ungdomsuddannelse_id: "",
        hjemmel_id: "",
        afgoerelsesbrev_id: "",
        revurderingsdato: "",
        befordringsudvalg: "",
        esdh_noegle: "",
        sagsbehandler_id: "",
        ppr_sagsbehandler_id: "",
        ansoegningsdato: "",
        sagsbehandlingsdato: iDagISO(),
        relation_til_barnet: "",
        foerste_koersel_dato: "",
        ansoegningstype: "",
        afstandskriterie_dato: "",
        afstandskriterie_klassetrin: "",
        hjaelpemiddel_ids: [],
      };
    }

    function resetCreateBevillingForm() {
      newBevilling = getEmptyBevilling();
      skoleType = null;
    }

    // Step 1's "Dato for første kørsel" seeds step 2's "Gyldig fra".
    //
    // Seed-once: only ever fills a gyldig_fra that is still empty, never
    // overwrites one the caseworker typed. Going back to step 1 and changing
    // the date therefore does not rewrite rows that already have a value —
    // a stale date is recoverable, a silently rewritten one is not.
    //
    // foerste_koersel_dato is nullable, so an empty step 1 simply seeds
    // nothing and step 2 behaves exactly as before.
    function seedGyldigFra(): string {
      return newBevilling.foerste_koersel_dato || "";
    }

    function makeEmptyModalEntry(): any {
      return {
        koersel: { tidspunkt_id: "", befordringstype_id: "", bevilget_koereafstand_pr_vej: "",
          gyldig_fra: seedGyldigFra(), gyldig_til: "", taxa_id: "", kommentar: "", rutetype_id: "",
          koersel_til_institution: "", max_minutter_i_transport: "",
          koerselsgodtgoerelse_modtager_id: "", koerselsgodtgoerelse_modtager_cpr: "", transporttid_i_bus: "", skift_med_bus: "" },
        dagIds: [] as number[],
        tillaegIds: [] as number[],
        dagSelectValue: "",
        tillaegSelectValue: "",
        distanceError: null as string | null,
        calculatingDistance: false,
      };
    }

    function makeModalEntryCopy(src: any): any {
      return {
        koersel: { ...src.koersel, gyldig_fra: src.koersel.gyldig_fra || seedGyldigFra(), gyldig_til: "" },
        dagIds: [...src.dagIds],
        tillaegIds: [...src.tillaegIds],
        dagSelectValue: "",
        tillaegSelectValue: "",
        distanceError: null,
        calculatingDistance: false,
      };
    }

    function resetModalKoerselEmpty() {
      modalKoerselList = [makeEmptyModalEntry()];
    }

    function resetModalKoersel(m: 'kopi' | 'tom', sourceBev?: any) {
      if (m === 'kopi') {
        const src = sourceBev?.koerselsraekker?.[0] ?? null;    
        if (src) {
          const rawTillaeg = src.tillaeg_ids ?? "";
          const rawDage = src.dag_ids ?? "";
          modalKoerselList = [{
            koersel: {
              tidspunkt_id: src.tidspunkt_id ?? "",
              befordringstype_id: src.befordringstype_id ?? "",
              bevilget_koereafstand_pr_vej: src.bevilget_koereafstand_pr_vej != null ? String(src.bevilget_koereafstand_pr_vej) : "",
              // Dates are NOT inherited from the copied bevilling — they come
              // from step 1, or are typed in step 2.
              gyldig_fra: seedGyldigFra(),
              gyldig_til: "",
              taxa_id: src.taxa_id ?? "",
              kommentar: src.kommentar ?? "",
              rutetype_id: src.rutetype_id ?? "",
              koersel_til_institution: src.koersel_til_institution != null ? String(src.koersel_til_institution) : "",
              max_minutter_i_transport: src.max_minutter_i_transport != null ? String(src.max_minutter_i_transport) : "",
              koerselsgodtgoerelse_modtager_id: src.koerselsgodtgoerelse_modtager_id ?? "",
              koerselsgodtgoerelse_modtager_cpr: src.koerselsgodtgoerelse_modtager_cpr ?? "",
              transporttid_i_bus: src.transporttid_i_bus != null ? String(src.transporttid_i_bus) : "",
              skift_med_bus: src.skift_med_bus != null ? String(src.skift_med_bus) : "",
            },
            dagIds: rawDage ? String(rawDage).split(",").map(Number).filter((n: number) => !isNaN(n)) : [],
            tillaegIds: rawTillaeg ? String(rawTillaeg).split(",").map(Number).filter((n: number) => !isNaN(n)) : [],
            dagSelectValue: "",
            tillaegSelectValue: "",
            distanceError: null,
            calculatingDistance: false,
          }];
        } else {
          resetModalKoerselEmpty();
        }
      } else {
        resetModalKoerselEmpty();
      }
    }

    // Classification is shared with KoerselsraekkeTable and BevillingTable via
    // $lib/koerselstype; these wrappers just bind the lookup list.
    const isModalKoerselEgenbefordring = (typeId: any) =>
      typeIsEgenbefordring(koerselstyper, typeId);

    const isModalKoerselTaxaType = (typeId: any) => typeIsTaxa(koerselstyper, typeId);

    const isModalKoerselSkolerejsekort = (typeId: any) =>
      typeIsSkolerejsekort(koerselstyper, typeId);

    async function calculateModalKoerselDistance(typeId: any, idx: number) {
      if (!isModalKoerselEgenbefordring(typeId)) {
        modalKoerselList[idx].koersel.bevilget_koereafstand_pr_vej = "";
        modalKoerselList = modalKoerselList;
        return;
      }

      modalKoerselList[idx].calculatingDistance = true;
      modalKoerselList[idx].distanceError = null;
      modalKoerselList = modalKoerselList;

      try {
        const { km, error } = await afstandFraKoordinater(
          newBevilling.adresse_lat,
          newBevilling.adresse_lon,
          newBevilling.matrikel_id
        );

        if (error !== null) {
          modalKoerselList[idx].distanceError = error;
          return;
        }

        // Discard if the user changed the type on this row while we calculated.
        if (Number(modalKoerselList[idx]?.koersel?.befordringstype_id) !== Number(typeId)) return;

        modalKoerselList[idx].koersel.bevilget_koereafstand_pr_vej = String(km);
      } finally {
        modalKoerselList[idx].calculatingDistance = false;
        modalKoerselList = modalKoerselList;
      }
    }

    function handleGoToStep2() { 
      modalError = null;
      if (newBevilling.ansoegningstype === "Midlertidig kørsel") {
        if (!skoleType) { modalError = "Vælg skoletype (Folkeskole eller Ungdomsuddannelse)"; return; }
        if (skoleType === 'folkeskole' && !newBevilling.matrikel_id) { modalError = "Folkeskole skal udfyldes"; return; }
        if (skoleType === 'ungdomsuddannelse' && !newBevilling.ungdomsuddannelse_id) { modalError = "Ungdomsuddannelse skal udfyldes"; return; }
      } else {
        if (!newBevilling.matrikel_id) { modalError = "Folkeskole skal udfyldes"; return; }
      }
      if (!newBevilling.hjemmel_id)         { modalError = "Hjemmel skal udfyldes"; return; }
      if (!newBevilling.afgoerelsesbrev_id) { modalError = "Afgørelsesbrev skal udfyldes"; return; }
      if (!newBevilling.sagsbehandler_id)   { modalError = "Sagsbehandler skal udfyldes"; return; }
      // ESDH-nøglen er sagens nummer i GO. Den er påkrævet HER, men ikke i
      // BevillingCreateRequest og ikke på databasekolonnen: OS2Forms opretter
      // gennem den samme vej, og en borgeransøgning har ingen sagsnøgle at
      // sende med — den tildeles først, når sagen oprettes.
      //
      // Når en sagsbehandler opretter i hånden, findes sagen derimod allerede,
      // og nøglen er det eneste der binder bevillingen til den: brevet
      // journaliseres på den, og det natlige job bygger linket til GO ud fra
      // den. Uden den ender bevillingen uden begge dele, uden at noget
      // klager.
      if (!newBevilling.esdh_noegle?.trim()) { modalError = "ESDH-nøgle skal udfyldes"; return; }

      // Required in this form only — NOT in BevillingCreateRequest or the
      // database column, both of which stay nullable because OS2Forms submits
      // through the same create path and a citizen's application may legitimately
      // arrive without the field. Tightening it there would reject the
      // submission outright.
      //
      // Here it guards the seeding below: without a date, gyldig_fra on step 2
      // is seeded with nothing and the caseworker is left wondering why.
      if (!newBevilling.foerste_koersel_dato) { modalError = "Dato for første kørsel skal udfyldes"; return; }

      // The first kørselsrække is built in onMount, before step 1 has been
      // filled in, so it cannot be seeded at construction. Fill it here on the
      // way into step 2 — still seed-once, so any row already carrying a date
      // keeps it.
      const seeded = seedGyldigFra();

      if (seeded) {
        modalKoerselList = modalKoerselList.map((entry: any) =>
          entry.koersel.gyldig_fra
            ? entry
            : { ...entry, koersel: { ...entry.koersel, gyldig_fra: seeded } }
        );
      }

      createBevillingStep = 2; 
    }

    function prefillFromBevilling(source: any) {
      skoleType = (source.ungdomsuddannelse_id && !source.matrikel_id) ? 'ungdomsuddannelse' : 'folkeskole';
      newBevilling = {
        adresse_id:                  source.adresse_id ?? null,
        adresse_tekst:               source.adresse_for_bevilling ?? "",
        adresse_lat:                 source.adresse_latitude ?? null,
        adresse_lon:                 source.adresse_longitude ?? null,
        matrikel_id:                 source.matrikel_id != null ? String(source.matrikel_id) : "",
        ungdomsuddannelse_id:        source.ungdomsuddannelse_id != null ? String(source.ungdomsuddannelse_id) : "",
        hjemmel_id:                  source.hjemmel_id != null ? String(source.hjemmel_id) : "",
        afgoerelsesbrev_id:          source.afgoerelsesbrev_id != null ? String(source.afgoerelsesbrev_id) : "",
        sagsbehandler_id:            source.sagsbehandler_id != null ? String(source.sagsbehandler_id) : "",
        ppr_sagsbehandler_id:        source.ppr_sagsbehandler_id != null ? String(source.ppr_sagsbehandler_id) : "",
        relation_til_barnet:         source.relation_til_barnet ?? "",
        ansoegningstype:             source.ansoegningstype ?? "",
        afstandskriterie_dato:       source.afstandskriterie_dato ? String(source.afstandskriterie_dato).slice(0, 10) : "",
        afstandskriterie_klassetrin: source.afstandskriterie_klassetrin != null ? String(source.afstandskriterie_klassetrin) : "",
        revurderingsdato:            source.revurderingsdato ? String(source.revurderingsdato).slice(0, 10) : "",
        befordringsudvalg:           source.befordringsudvalg ? String(source.befordringsudvalg).slice(0, 10) : "",
        // A revurdering continues the same ESDH case, so the key carries over.
        // The other fields below stay blank on purpose: they belong to the new
        // bevilling, not the one being copied.
        esdh_noegle:                 source.esdh_noegle ?? "",
        ansoegningsdato:             "",
        sagsbehandlingsdato:         iDagISO(),
        foerste_koersel_dato:        "",
        hjaelpemiddel_ids:           [],
      };
    }

    async function handleCreateBevilling() {
      modalError = null;
      if (newBevilling.ansoegningstype === "Midlertidig kørsel") {
        if (!skoleType) { modalError = "Vælg skoletype (Folkeskole eller Ungdomsuddannelse)"; return; }
        if (skoleType === 'folkeskole' && !newBevilling.matrikel_id) { modalError = "Folkeskole skal udfyldes"; return; }
        if (skoleType === 'ungdomsuddannelse' && !newBevilling.ungdomsuddannelse_id) { modalError = "Ungdomsuddannelse skal udfyldes"; return; }
      } else {
        if (!newBevilling.matrikel_id) { modalError = "Folkeskole skal udfyldes"; return; }
      }
      if (!newBevilling.adresse_id)        { modalError = "Adresse for bevilling skal udfyldes"; return; }
      if (!newBevilling.hjemmel_id)         { modalError = "Hjemmel skal udfyldes"; return; }
      if (!newBevilling.afgoerelsesbrev_id) { modalError = "Afgørelsesbrev skal udfyldes"; return; }
      if (!newBevilling.sagsbehandler_id)   { modalError = "Sagsbehandler skal udfyldes"; return; }
      // Samme krav som i handleGoToStep2 — se begrundelsen der.
      if (!newBevilling.esdh_noegle?.trim()) { modalError = "ESDH-nøgle skal udfyldes"; return; }
      if (!validateBevillingDates()) return;
      const payload = {
        adresse_id:                  newBevilling.adresse_id,
        matrikel_id:                 (isMidlertidig && skoleType === 'ungdomsuddannelse') ? null : numberOrNull(newBevilling.matrikel_id),
        ungdomsuddannelse_id:        (isMidlertidig && skoleType === 'ungdomsuddannelse') ? numberOrNull(newBevilling.ungdomsuddannelse_id) : null,
        hjemmel_id:                  numberOrNull(newBevilling.hjemmel_id),
        afgoerelsesbrev_id:          numberOrNull(newBevilling.afgoerelsesbrev_id),
        revurderingsdato:            emptyToNull(newBevilling.revurderingsdato),
        befordringsudvalg:           isMidlertidig ? null : emptyToNull(newBevilling.befordringsudvalg),
        esdh_noegle:                 emptyToNull(newBevilling.esdh_noegle),
        sagsbehandler_id:            numberOrNull(newBevilling.sagsbehandler_id),
        ppr_sagsbehandler_id:        isMidlertidig ? null : numberOrNull(newBevilling.ppr_sagsbehandler_id),
        ansoegningsdato:             emptyToNull(newBevilling.ansoegningsdato),
        sagsbehandlingsdato:         emptyToNull(newBevilling.sagsbehandlingsdato),
        relation_til_barnet:         emptyToNull(newBevilling.relation_til_barnet),
        foerste_koersel_dato:        emptyToNull(newBevilling.foerste_koersel_dato),
        ansoegningstype:             emptyToNull(newBevilling.ansoegningstype),
        afstandskriterie_dato:       isMidlertidig ? null : emptyToNull(newBevilling.afstandskriterie_dato),
        afstandskriterie_klassetrin: isMidlertidig ? null : numberOrNull(newBevilling.afstandskriterie_klassetrin),
        hjaelpemiddel_ids:           newBevilling.hjaelpemiddel_ids ?? [],
      };
      const res = await backendFetch(
        `/bevilling/create_bevilling/${cpr}?status_text=${encodeURIComponent("Kommende")}`,
        { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(payload) }
      );
      if (!res.ok) {
        let message = "Kunne ikke oprette bevilling";
        try {
          const err = await res.json();
          message = err?.detail?.message ?? (Array.isArray(err?.detail) ? err.detail.map((e: any) => e.msg ?? JSON.stringify(e)).join("\n") : err?.detail) ?? message;
        } catch { /* keep fallback */ }
        modalError = `Fejl ${res.status}: ${message}`;
        return;
      }
      dispatch('created');
    }

    async function handleCreateBevillingAndKoersel() {
      modalError = null;
      if (!newBevilling.adresse_id) { modalError = "Adresse mangler"; return; }
      if (!validateBevillingDates()) return;

      for (let i = 0; i < modalKoerselList.length; i++) {
        const entry = modalKoerselList[i];
        const krs = entry.koersel;
        const prefix = modalKoerselList.length > 1 ? `Kørselsrække ${i + 1}: ` : "";
        if (!krs.befordringstype_id) { modalError = `${prefix}Kørselstype skal udfyldes`; return; }
        if (!krs.gyldig_fra)         { modalError = `${prefix}Gyldig fra skal udfyldes`; return; }
        if (!krs.gyldig_til)         { modalError = `${prefix}Gyldig til skal udfyldes`; return; }
        if (isDateOutOfRange(krs.gyldig_fra)) { modalError = `${prefix}Gyldig fra: Dato er ugyldig — kontrollér årstallet`; return; }
        if (isDateOutOfRange(krs.gyldig_til)) { modalError = `${prefix}Gyldig til: Dato er ugyldig — kontrollér årstallet`; return; }
        if (krs.gyldig_fra && krs.gyldig_til && krs.gyldig_fra > krs.gyldig_til) {
          modalError = `${prefix}Gyldig fra kan ikke være efter gyldig til`; return;
        }
        if (entry.dagIds.length === 0) { modalError = `${prefix}Mindst én dag skal vælges`; return; }
        if (!krs.rutetype_id) { modalError = `${prefix}Rutetype skal udfyldes`; return; }
        if (isModalKoerselEgenbefordring(krs.befordringstype_id)) {
          if (!krs.bevilget_koereafstand_pr_vej) { modalError = `${prefix}Bevilget km pr. vej skal udfyldes`; return; }
          if (!krs.koerselsgodtgoerelse_modtager_id && !krs.koerselsgodtgoerelse_modtager_cpr) { modalError = `${prefix}Kørselsgodtgørelse modtager skal udfyldes`; return; }
        }
        if (isModalKoerselTaxaType(krs.befordringstype_id) && harEftermiddagsTur(krs.rutetype_id)) {
          // Only asked for where it applies — the field is hidden on a
          // morning-only kørsel, and a hidden field cannot be required.
          if (krs.koersel_til_institution === "" || krs.koersel_til_institution == null) {
            modalError = `${prefix}Kørsel til institution skal udfyldes`; return;
          }
        }
        if (isModalKoerselSkolerejsekort(krs.befordringstype_id)) {
          if (krs.transporttid_i_bus === "" || krs.transporttid_i_bus == null) { modalError = `${prefix}Transporttid i bus skal udfyldes`; return; }
          if (krs.skift_med_bus === "" || krs.skift_med_bus == null) { modalError = `${prefix}Antal skift skal udfyldes`; return; }
        }
      }
      
      isCreatingKoerselInModal = true;
      const isMidlertidig = newBevilling.ansoegningstype === "Midlertidig kørsel";
      const bevPayload = {
        adresse_id:                  newBevilling.adresse_id,
        matrikel_id:                 (isMidlertidig && skoleType === 'ungdomsuddannelse') ? null : numberOrNull(newBevilling.matrikel_id),
        ungdomsuddannelse_id:        (isMidlertidig && skoleType === 'ungdomsuddannelse') ? numberOrNull(newBevilling.ungdomsuddannelse_id) : null,
        hjemmel_id:                  numberOrNull(newBevilling.hjemmel_id),
        afgoerelsesbrev_id:          numberOrNull(newBevilling.afgoerelsesbrev_id),
        revurderingsdato:            emptyToNull(newBevilling.revurderingsdato),
        befordringsudvalg:           emptyToNull(newBevilling.befordringsudvalg),
        esdh_noegle:                 emptyToNull(newBevilling.esdh_noegle),
        sagsbehandler_id:            numberOrNull(newBevilling.sagsbehandler_id),
        ppr_sagsbehandler_id:        numberOrNull(newBevilling.ppr_sagsbehandler_id),
        ansoegningsdato:             emptyToNull(newBevilling.ansoegningsdato),
        sagsbehandlingsdato:         emptyToNull(newBevilling.sagsbehandlingsdato),
        relation_til_barnet:         emptyToNull(newBevilling.relation_til_barnet),
        foerste_koersel_dato:        emptyToNull(newBevilling.foerste_koersel_dato),
        ansoegningstype:             emptyToNull(newBevilling.ansoegningstype),
        afstandskriterie_dato:       emptyToNull(newBevilling.afstandskriterie_dato),
        afstandskriterie_klassetrin: numberOrNull(newBevilling.afstandskriterie_klassetrin),
        hjaelpemiddel_ids:           newBevilling.hjaelpemiddel_ids ?? [],
      };
      try {
        const bevRes = await backendFetch(
          `/bevilling/create_bevilling/${cpr}?status_text=${encodeURIComponent("Kommende")}`,
          { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(bevPayload) }
        );
        if (!bevRes.ok) {
          let message = "Kunne ikke oprette bevilling";
          try { const err = await bevRes.json(); message = err?.detail?.message ?? err?.detail ?? message; } catch { /* keep fallback */ }
          modalError = `Fejl ${bevRes.status}: ${message}`;
          return;
        }
        const { bevilling_id: newBevillingId } = await bevRes.json();

        for (let i = 0; i < modalKoerselList.length; i++) {
          const entry = modalKoerselList[i];
          const krs = entry.koersel;
          const prefix = modalKoerselList.length > 1 ? `Kørselsrække ${i + 1}: ` : "";
          const isEgb = isModalKoerselEgenbefordring(krs.befordringstype_id);
          const isTxa = isModalKoerselTaxaType(krs.befordringstype_id);
          const isSRK = isModalKoerselSkolerejsekort(krs.befordringstype_id);
          const krPayload = {
            tidspunkt_id:                     numberOrNull(krs.tidspunkt_id),
            befordringstype_id:               numberOrNull(krs.befordringstype_id),
            bevilget_koereafstand_pr_vej:     isEgb ? (Number(krs.bevilget_koereafstand_pr_vej) || 0) : null,
            gyldig_fra:                       krs.gyldig_fra || null,
            gyldig_til:                       krs.gyldig_til || null,
            rutetype_id:                      numberOrNull(krs.rutetype_id),
            taxa_id:                          isTxa ? (krs.taxa_id || null) : null,
            kommentar:                        krs.kommentar || "",
            final:                            false,
            tillaeg_ids:                      isTxa ? entry.tillaegIds : [],
            dag_ids:                          entry.dagIds,
            transporttid_i_bus:               isSRK ? numberOrNull(krs.transporttid_i_bus) : null,
            skift_med_bus:                    isSRK ? numberOrNull(krs.skift_med_bus) : null,
            // Nulled when it does not apply, not merely hidden: answering "Ja"
            // under Eftermiddag and then switching to Morgen would otherwise
            // leave a morning kørsel claiming it goes to an institution, and
            // the afgørelsesbrev would gain an SFO paragraph for a journey
            // that does not exist.
            koersel_til_institution:          isTxa && harEftermiddagsTur(krs.rutetype_id)
              ? (krs.koersel_til_institution === 'true' || krs.koersel_til_institution === true)
              : null,
            max_minutter_i_transport:         isTxa ? numberOrNull(krs.max_minutter_i_transport) : null,
            koerselsgodtgoerelse_modtager_id: isEgb ? numberOrNull(krs.koerselsgodtgoerelse_modtager_id) : null,
            koerselsgodtgoerelse_modtager_cpr: isEgb ? (krs.koerselsgodtgoerelse_modtager_cpr || null) : null,
          };
          const krRes = await backendFetch(
            `/bevilling/create_koerselsraekke/${newBevillingId}`,
            { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(krPayload) }
          );
          if (!krRes.ok) {
            let message = "Ukendt fejl";
            try { const err = await krRes.json(); message = err?.detail?.message ?? err?.detail ?? message; } catch { /* keep fallback */ }
            modalError = `Bevilling oprettet, men ${prefix.toLowerCase().trim() || 'kørselsrækken'}fejlede: ${message}`;
            return;
          }
        }
        dispatch('created');
      } finally {
        isCreatingKoerselInModal = false;
      }
    }

    onMount(() => {
      createBevillingStep = 1;
      resetCreateBevillingForm();
      if (mode === 'kopi') {
        // The top of the dropdown, which is sorted by status rank — see
        // $lib/statusRang. Preselecting the Aktiv one instead meant the modal
        // opened on the second entry whenever a student had a Fejlet
        // bevilling above it. The caseworker can still pick any of them; the
        // status is shown next to each.
        const activeBev = primaerBevilling(existingBevillinger as any[]) ?? existingBevillinger[0];
        selectedSourceBevillingId = activeBev?.bevilling_id ?? null;
        resetModalKoersel('kopi', activeBev);
        if (activeBev) prefillFromBevilling(activeBev);
      } else {
        resetModalKoersel('tom');

        // A student has one ESDH case across all their bevillinger, so a
        // bevilling created from blank belongs to the same case as the ones
        // already on the student. Only the "kopi" path used to carry the key
        // over, leaving the caseworker to retype it here.
        //
        // Which bevilling it is read from only matters where they disagree,
        // and then the current one is the right answer — hence the same
        // ranking the nightly sync uses: aktiv, then kommende, then the
        // bevilling whose kørsel ran latest.
        const gaeldende = vaelgGaeldendeBevilling(existingBevillinger);

        if (gaeldende?.esdh_noegle) {
          newBevilling = { ...newBevilling, esdh_noegle: gaeldende.esdh_noegle };
        }
      }

      // Last, so it also wins over a copied bevilling's values: those were
      // right for the klassetrin the student was in then, and a revurdering is
      // precisely when that has moved on.
      applyBeregnetAfstandskriterie();
    });
  </script>

  <!-- Backdrop — absent in standalone mode, where the form is the page. -->
  <div
    class={standalone
      ? "min-h-screen bg-white"
      : "fixed inset-0 z-50 flex items-center justify-center bg-black/40"}
    role="presentation"
  >
    <div
      class={standalone
        ? "w-full bg-white"
        : "w-[1150px] max-h-[90vh] overflow-y-auto bg-white rounded-lg shadow-2xl"}
      role="dialog"
      aria-modal={standalone ? "false" : "true"}
      tabindex="-1"
    >

      <div class="sticky top-0 z-10 px-8 py-5 border-b border-gray-200" style="background-color: #032A42;">
        <h2 class="text-lg font-bold text-white">Opret ny bevilling</h2>
        <p class="mt-0.5 text-sm" style="color: rgba(255,255,255,0.7);">
          {createBevillingStep === 1 ? 'Trin 1 af 2 — Bevillingsoplysninger' : 'Trin 2 af 2 — Kørselsrække'}
        </p>
      </div>

     {#if createBevillingStep === 1}
      <div class="p-8">
        <div class="grid grid-cols-2 gap-5">

          {#if mode === 'kopi'}
          <label class="text-sm font-medium text-gray-700 col-span-2">
            Kopier fra bevilling
            <select
              class="mt-1.5 w-full border border-gray-300 rounded px-3 py-2 text-sm"
              bind:value={selectedSourceBevillingId}
              on:change={() => {
                const bev = existingBevillinger.find((b: any) => b.bevilling_id === selectedSourceBevillingId) ?? null;
                if (bev) { prefillFromBevilling(bev); resetModalKoersel('kopi', bev); applyBeregnetAfstandskriterie(); }
              }}
            >
              {#each existingBevillinger as bev}
                <option value={bev.bevilling_id}>{bevillingLabel(bev)} — {bev.status_tekst ?? 'Ukendt status'}</option>
              {/each}
            </select>
          </label>
          {/if}

          <label class="text-sm font-medium text-gray-700 col-span-2">
            Kørsel <span class="text-red-500">*</span>
            <select class="mt-1.5 w-full border border-gray-300 rounded px-3 py-2 text-sm" bind:value={newBevilling.ansoegningstype} on:change={onAnsoegningstypeChange}>
              <option value="">Vælg</option>
              <option value="Fast kørsel">Fast kørsel</option>
              <option value="Midlertidig kørsel">Midlertidig kørsel</option>
            </select>
          </label>

          {#if newBevilling.ansoegningstype === "Midlertidig kørsel"}
            <div class="col-span-2">
              <p class="text-sm font-medium text-gray-700 mb-2">Skole type <span class="text-red-500">*</span></p>
              <div class="flex gap-2">
                <button type="button"
                  class="flex-1 py-2 text-sm font-medium rounded border transition-colors"
                  style={skoleType === 'folkeskole' ? 'background-color:#032A42;color:#fff;border-color:#032A42;' : 'background-color:#fff;color:#374151;border-color:#d1d5db;'}
                  on:click={() => { skoleType = 'folkeskole'; resetLookupSelections(); }}>Folkeskole</button>
                <button type="button"
                  class="flex-1 py-2 text-sm font-medium rounded border transition-colors"
                  style={skoleType === 'ungdomsuddannelse' ? 'background-color:#032A42;color:#fff;border-color:#032A42;' : 'background-color:#fff;color:#374151;border-color:#d1d5db;'}
                  on:click={() => { skoleType = 'ungdomsuddannelse'; resetLookupSelections(); }}>Ungdomsuddannelse</button>
              </div>
            </div>
            {#if skoleType === 'folkeskole'}
              <label class="text-sm font-medium text-gray-700 col-span-2">
                Folkeskole (matrikel) <span class="text-red-500">*</span>
                <select class="mt-1.5 w-full border border-gray-300 rounded px-3 py-2 text-sm" bind:value={newBevilling.matrikel_id}>
                  <option value="">Vælg</option>
                  {#each lookupOptions.skolematrikler ?? [] as option}
                    <option value={String(option.id)}>{option.label}</option>
                  {/each}
                </select>
              </label>
            {:else if skoleType === 'ungdomsuddannelse'}
              <label class="text-sm font-medium text-gray-700 col-span-2">
                Ungdomsuddannelse <span class="text-red-500">*</span>
                <select class="mt-1.5 w-full border border-gray-300 rounded px-3 py-2 text-sm" bind:value={newBevilling.ungdomsuddannelse_id}>
                  <option value="">Vælg</option>
                  {#each lookupOptions.ungdomsuddannelser ?? [] as option}
                    <option value={String(option.id)}>{option.label}</option>
                  {/each}
                </select>
              </label>
            {/if}
          {:else if newBevilling.ansoegningstype}
            <label class="text-sm font-medium text-gray-700 col-span-2">
              Folkeskole (matrikel) <span class="text-red-500">*</span>
              <select class="mt-1.5 w-full border border-gray-300 rounded px-3 py-2 text-sm" bind:value={newBevilling.matrikel_id}>
                <option value="">Vælg</option>
                {#each lookupOptions.skolematrikler ?? [] as option}
                  <option value={String(option.id)}>{option.label}</option>
                {/each}
              </select>
            </label>
          {/if}

          {#if (newBevilling.ansoegningstype && newBevilling.ansoegningstype !== "Midlertidig kørsel") || (newBevilling.ansoegningstype === "Midlertidig kørsel" && skoleType !== null)}

            <label class="text-sm font-medium text-gray-700 col-span-2">
              Adresse for bevilling <span class="text-red-500">*</span>
              <div class="mt-1.5">
                <AddresseSearch
                  adresseId={newBevilling.adresse_id}
                  adresseTekst={newBevilling.adresse_tekst}
                  onSelect={(result) => {
                    newBevilling = {
                      ...newBevilling,
                      adresse_id: result?.adresse_id ?? null,
                      adresse_tekst: result?.adresse_tekst ?? "",
                      adresse_lat: result?.latitude ?? null,
                      adresse_lon: result?.longitude ?? null,
                    };
                  }}
                />
              </div>
            </label>

            <label class="text-sm font-medium text-gray-700">
              Hjemmel <span class="text-red-500">*</span>
              <select class="mt-1.5 w-full border border-gray-300 rounded px-3 py-2 text-sm" bind:value={newBevilling.hjemmel_id}
                on:change={() => { newBevilling = { ...newBevilling, afgoerelsesbrev_id: "" }; }}>
                <option value="">Vælg</option>
                {#each visibleHjemler as option}
                  <option value={String(option.id)}>{option.label}</option>
                {/each}
              </select>
            </label>

            <label class="text-sm font-medium text-gray-700">
              Afgørelsesbrev <span class="text-red-500">*</span>
              <select class="mt-1.5 w-full border border-gray-300 rounded px-3 py-2 text-sm" bind:value={newBevilling.afgoerelsesbrev_id}>
                <option value="">Vælg</option>
                {#each visibleAfgoerelsesbreve as option}
                  <option value={String(option.id)}>{option.label}</option>
                {/each}
              </select>
            </label>

            <label class="text-sm font-medium text-gray-700">
              Revurdering
              <input type="date" min={MIN_DATE} max={MAX_DATE} class="mt-1.5 w-full border border-gray-300 rounded px-3 py-2 text-sm" bind:value={newBevilling.revurderingsdato} />
            </label>

            {#if !isMidlertidig}
            <label class="text-sm font-medium text-gray-700">
              Befordringsudvalg
              <input type="date" min={MIN_DATE} max={MAX_DATE} class="mt-1.5 w-full border border-gray-300 rounded px-3 py-2 text-sm" bind:value={newBevilling.befordringsudvalg} />
            </label>
            {/if}

            <label class="text-sm font-medium text-gray-700">
              ESDH-nøgle <span class="text-red-500">*</span>
              <input class="mt-1.5 w-full border border-gray-300 rounded px-3 py-2 text-sm" bind:value={newBevilling.esdh_noegle} />
              <span class="mt-1 block text-xs font-normal text-gray-500">Sagens nummer i GO, fx PPR-2026-123456-001</span>
            </label>

            <label class="text-sm font-medium text-gray-700">
              Sagsbehandler <span class="text-red-500">*</span>
              <select class="mt-1.5 w-full border border-gray-300 rounded px-3 py-2 text-sm" bind:value={newBevilling.sagsbehandler_id}>
                <option value="">Vælg</option>
                {#each lookupOptions.sagsbehandlere ?? [] as option}
                  <option value={String(option.id)}>{option.label}</option>
                {/each}
              </select>
            </label>

            {#if !isMidlertidig}
            <label class="text-sm font-medium text-gray-700">
              PPR ansvarlig
              <select class="mt-1.5 w-full border border-gray-300 rounded px-3 py-2 text-sm" bind:value={newBevilling.ppr_sagsbehandler_id}>
                <option value="">Vælg</option>
                {#each lookupOptions.pprSagsbehandlere ?? [] as option}
                  <option value={String(option.id)}>{option.label}</option>
                {/each}
              </select>
            </label>
            {/if}

            <label class="text-sm font-medium text-gray-700">
              Sagsbehandlingsdato
              <input type="date" min={MIN_DATE} max={MAX_DATE} class="mt-1.5 w-full border border-gray-300 rounded px-3 py-2 text-sm" bind:value={newBevilling.sagsbehandlingsdato} />
            </label>

            <label class="text-sm font-medium text-gray-700">
              Ansøger relation
              <select class="mt-1.5 w-full border border-gray-300 rounded px-3 py-2 text-sm" bind:value={newBevilling.relation_til_barnet}>
                <option value="">Vælg</option>
                {#each ansoegerRelationOptions(newBevilling.relation_til_barnet) as relation}
                  <option value={relation}>{relation}</option>
                {/each}
              </select>
            </label>

            <label class="text-sm font-medium text-gray-700">
              Dato for første kørsel <span class="text-red-500">*</span>
              <input type="date" min={MIN_DATE} max={MAX_DATE} class="mt-1.5 w-full border border-gray-300 rounded px-3 py-2 text-sm" bind:value={newBevilling.foerste_koersel_dato} />
            </label>

            {#if !isMidlertidig}
            <label class="text-sm font-medium text-gray-700">
              Afstandskriterie dato
              <input type="date" min={MIN_DATE} max={MAX_DATE} class="mt-1.5 w-full border border-gray-300 rounded px-3 py-2 text-sm" bind:value={newBevilling.afstandskriterie_dato} />
              {#if beregnetDato}
                <span class="mt-1 block text-[11px] font-normal text-gray-500">
                  Beregnet ud fra elevens klassetrin — kan rettes
                </span>
              {/if}
            </label>
            {/if}

            {#if !isMidlertidig}
            <label class="text-sm font-medium text-gray-700">
              Afstandskriterie klassetrin
              <select class="mt-1.5 w-full border border-gray-300 rounded px-3 py-2 text-sm" bind:value={newBevilling.afstandskriterie_klassetrin}>
                <option value="">Vælg</option>
                {#each klassetrinOptions(newBevilling.afstandskriterie_klassetrin) as trin}
                  <option value={trin}>{trin}</option>
                {/each}
              </select>
              {#if beregnetKlassetrin !== null}
                <span class="mt-1 block text-[11px] font-normal text-gray-500">
                  Beregnet ud fra elevens klassetrin — kan rettes
                </span>
              {/if}
            </label>
            {/if}

            <!-- Begrundelse was here. The column and the OS2Forms writer both
                 remain — an application still carries its begrundelse — but it
                 is no longer set by hand from this modal. -->
            <label class="text-sm font-medium text-gray-700">
              Ansøgningsdato
              <input type="date" min={MIN_DATE} max={MAX_DATE} class="mt-1.5 w-full border border-gray-300 rounded px-3 py-2 text-sm" bind:value={newBevilling.ansoegningsdato} />
            </label>

          {/if}

        </div>
      </div>

      {:else}


      <!-- Step 2: Kørselsrækker -->
      <div class="p-6">

        {#each modalKoerselList as entry, i}
          {@const krs = entry.koersel}
          {@const isEgb = isModalKoerselEgenbefordring(krs.befordringstype_id)}
          {@const isTxa = isModalKoerselTaxaType(krs.befordringstype_id)}
          {@const isSRK = isModalKoerselSkolerejsekort(krs.befordringstype_id)}

          <div class="mb-4 {modalKoerselList.length > 1 ? 'border border-gray-200 rounded-lg p-4' : ''}">

            {#if modalKoerselList.length > 1}
              <div class="flex items-center justify-between mb-3">
                <span class="text-xs font-semibold uppercase tracking-wider text-gray-500">Kørselsrække {i + 1}</span>
                <button type="button"
                  class="p-1 text-gray-400 hover:text-red-600 transition-colors"
                  title="Fjern kørselsrække"
                  on:click={() => { modalKoerselList = modalKoerselList.filter((_, idx) => idx !== i); }}>
                  <svg class="w-4 h-4" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                  </svg>
                </button>
              </div>
            {/if}

            <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-x-5 gap-y-4">

              <!-- Kørselstype — always Row 1, col 1 -->
              <label class="block">
                <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 block">Kørselstype *</span>
                <select class="border border-gray-300 px-2 py-1.5 text-sm rounded w-full focus:border-blue-400 focus:ring-0"
                  value={krs.befordringstype_id ?? ""}
                  on:change={(e) => {
                    const val = e.currentTarget.value === "" ? "" : Number(e.currentTarget.value);
                    modalKoerselList[i].koersel.befordringstype_id = val;
                    if (!isModalKoerselTaxaType(val)) modalKoerselList[i].tillaegIds = [];
                    modalKoerselList = modalKoerselList;
                    calculateModalKoerselDistance(val, i);
                  }}
                >
                  <option value="">Vælg</option>
                  {#each availableModalKoerselstyper as opt}<option value={opt.id}>{opt.label}</option>{/each}
                </select>
              </label>

              <!-- Row 1, shared: Tidspunkt | Rutetype | Dage -->
              <label class="block">
                <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 block">Tidspunkt</span>
                <select class="border border-gray-300 px-2 py-1.5 text-sm rounded w-full focus:border-blue-400 focus:ring-0"
                  value={krs.tidspunkt_id ?? ""}
                  on:change={(e) => { modalKoerselList[i].koersel.tidspunkt_id = e.currentTarget.value === "" ? "" : Number(e.currentTarget.value); modalKoerselList = modalKoerselList; }}>
                  <option value="">Vælg</option>
                  {#each tidspunkter as opt}<option value={opt.id}>{opt.label}</option>{/each}
                </select>
              </label>
              <label class="block">
                <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 block">Rutetype *</span>
                <select class="border border-gray-300 px-2 py-1.5 text-sm rounded w-full focus:border-blue-400 focus:ring-0"
                  value={krs.rutetype_id ?? ""}
                  on:change={(e) => { modalKoerselList[i].koersel.rutetype_id = e.currentTarget.value === "" ? "" : Number(e.currentTarget.value); modalKoerselList = modalKoerselList; }}>
                  <option value="">Vælg</option>
                  {#each lookupOptions.rutetyper ?? [] as opt}<option value={opt.id}>{opt.label}</option>{/each}
                </select>
              </label>
              <div>
                <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 block">Dage *</span>
                <DagePicker options={dage} bind:selected={modalKoerselList[i].dagIds} />
              </div>

              {#if isEgb}
                <!-- Egenbefordring: Row 2: Bevilget km | Kørselsgodtgørelse modtager | empty | empty -->
                <label class="block md:col-start-1">
                  <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 flex items-center gap-1.5">
                    Bevilget km pr. vej *
                    {#if entry.calculatingDistance}<span class="text-blue-500 font-normal normal-case text-[10px]">beregner...</span>{/if}
                  </span>
                  <input type="number" step="0.1" class="border border-gray-300 px-2 py-1.5 text-sm rounded w-full focus:border-blue-400 focus:ring-0 {entry.calculatingDistance ? 'opacity-50' : ''}"
                    disabled={entry.calculatingDistance}
                    value={krs.bevilget_koereafstand_pr_vej ?? ""} on:change={(e) => { modalKoerselList[i].koersel.bevilget_koereafstand_pr_vej = e.currentTarget.value; modalKoerselList = modalKoerselList; }} />
                </label>
                <label class="block">
                  <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 block">Kørselsgodtgørelse modtager *</span>
                  <select class="border border-gray-300 px-2 py-1.5 text-sm rounded w-full focus:border-blue-400 focus:ring-0"
                    value={krs.koerselsgodtgoerelse_modtager_id ? `p:${krs.koerselsgodtgoerelse_modtager_id}` : krs.koerselsgodtgoerelse_modtager_cpr ? `f:${krs.koerselsgodtgoerelse_modtager_cpr}` : ""}
                    on:change={(e) => {
                      const v = e.currentTarget.value;
                      if (!v) { modalKoerselList[i].koersel.koerselsgodtgoerelse_modtager_id = ""; modalKoerselList[i].koersel.koerselsgodtgoerelse_modtager_cpr = ""; }
                      else if (v.startsWith("p:")) { modalKoerselList[i].koersel.koerselsgodtgoerelse_modtager_id = Number(v.slice(2)); modalKoerselList[i].koersel.koerselsgodtgoerelse_modtager_cpr = ""; }
                      else if (v.startsWith("f:")) { modalKoerselList[i].koersel.koerselsgodtgoerelse_modtager_id = ""; modalKoerselList[i].koersel.koerselsgodtgoerelse_modtager_cpr = v.slice(2); }
                      modalKoerselList = modalKoerselList;
                    }}>
                    <option value="">Vælg</option>
                    {#if parter.some((r: any) => r.type === 'foraelder')}
                      <optgroup label="Forældre">
                        {#each parter.filter((r: any) => r.type === 'foraelder') as r}
                          <option value="f:{r.cpr_foraelder}">{r.fulde_navn ?? r.cpr_foraelder}{r.relation ? ` (${r.relation})` : ""}</option>
                        {/each}
                      </optgroup>
                    {/if}
                    {#if parter.some((r: any) => r.type === 'part')}
                      <optgroup label="Øvrige parter">
                        {#each parter.filter((r: any) => r.type === 'part') as r}
                          <option value="p:{r.part_id}">{r.fulde_navn ?? r.part_id}{r.relation ? ` (${r.relation})` : ""}</option>
                        {/each}
                      </optgroup>
                    {/if}
                  </select>
                </label>
                <div></div><div></div>
                <!-- Row 3: Gyldig fra | Gyldig til | empty | empty -->
                <label class="block md:col-start-1">
                  <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 block">Gyldig fra *</span>
                  <input type="date" min={MIN_DATE} max={MAX_DATE} class="border border-gray-300 px-2 py-1.5 text-sm rounded w-full focus:border-blue-400 focus:ring-0"
                    value={krs.gyldig_fra ?? ""} on:change={(e) => { modalKoerselList[i].koersel.gyldig_fra = e.currentTarget.value; modalKoerselList = modalKoerselList; }} />
                </label>
                <label class="block">
                  <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 block">Gyldig til *</span>
                  <input type="date" min={MIN_DATE} max={MAX_DATE} class="border border-gray-300 px-2 py-1.5 text-sm rounded w-full focus:border-blue-400 focus:ring-0"
                    value={krs.gyldig_til ?? ""} on:change={(e) => { modalKoerselList[i].koersel.gyldig_til = e.currentTarget.value; modalKoerselList = modalKoerselList; }} />
                </label>
                <div></div><div></div>
                <!-- Row 4: Kommentar -->
                <label class="block md:col-start-1 md:col-span-4">
                  <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 block">Kommentar</span>
                  <textarea class={kommentarClass} rows="3"
                    value={krs.kommentar ?? ""} on:change={(e) => { modalKoerselList[i].koersel.kommentar = e.currentTarget.value; modalKoerselList = modalKoerselList; }}></textarea>
                </label>

              {:else if isTxa}
                <!-- Taxa: Row 2: Tillæg | Kørsel til institution | Max min | Taxa-ID -->
                <div class="md:col-start-1">
                  <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 block">Tillæg</span>
                  <div class="border border-gray-300 rounded p-2">
                    <div class="mb-1.5 flex flex-wrap gap-1">
                      {#each entry.tillaegIds as id}
                        {@const opt = koerselstypeTillaeg.find((t: any) => Number(t.id) === id)}
                        <span class="inline-flex items-center gap-1 rounded bg-slate-100 px-1.5 py-0.5 text-xs">
                          {opt?.label ?? id}
                          <button type="button" class="text-red-500 hover:text-red-700 font-bold"
                            on:click={() => { modalKoerselList[i].tillaegIds = entry.tillaegIds.filter((x: number) => x !== id); modalKoerselList = modalKoerselList; }}>×</button>
                        </span>
                      {/each}
                    </div>
                    <select class="w-full border-0 border-t border-gray-200 pt-1 text-xs text-gray-600 focus:ring-0"
                      value={entry.tillaegSelectValue}
                      on:change={(e) => {
                        const val = Number(e.currentTarget.value);
                        if (val && !entry.tillaegIds.includes(val)) { modalKoerselList[i].tillaegIds = [...entry.tillaegIds, val]; }
                        modalKoerselList[i].tillaegSelectValue = "";
                        modalKoerselList = modalKoerselList;
                      }}>
                      <option value="">Tilføj tillæg</option>
                      {#each koerselstypeTillaeg.filter((t: any) => !entry.tillaegIds.includes(Number(t.id))) as opt}
                        <option value={String(opt.id)}>{opt.label}</option>
                      {/each}
                    </select>
                  </div>
                </div>
                {#if harEftermiddagsTur(krs.rutetype_id)}
                <label class="block">
                  <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 block">Kørsel til institution *</span>
                  <select class="border border-gray-300 px-2 py-1.5 text-sm rounded w-full focus:border-blue-400 focus:ring-0"
                    value={krs.koersel_til_institution != null && krs.koersel_til_institution !== "" ? String(krs.koersel_til_institution) : ""}
                    on:change={(e) => { modalKoerselList[i].koersel.koersel_til_institution = e.currentTarget.value; modalKoerselList = modalKoerselList; }}>
                    <option value="">Vælg</option>
                    <option value="true">Ja</option>
                    <option value="false">Nej</option>
                  </select>
                </label>
                {/if}
                <label class="block">
                  <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 block">Max. antal min. i transport</span>
                  <input type="number" min="0" max="500" class="border border-gray-300 px-2 py-1.5 text-sm rounded w-full focus:border-blue-400 focus:ring-0"
                    value={krs.max_minutter_i_transport ?? ""} on:change={(e) => { modalKoerselList[i].koersel.max_minutter_i_transport = e.currentTarget.value; modalKoerselList = modalKoerselList; }} />
                </label>
                <label class="block">
                  <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 block">Taxa-ID</span>
                  <input class="border border-gray-300 px-2 py-1.5 text-sm rounded w-full focus:border-blue-400 focus:ring-0"
                    value={krs.taxa_id ?? ""} on:change={(e) => { modalKoerselList[i].koersel.taxa_id = e.currentTarget.value; modalKoerselList = modalKoerselList; }} />
                </label>
                <!-- Row 3: Gyldig fra | Gyldig til | empty | empty -->
                <label class="block md:col-start-1">
                  <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 block">Gyldig fra *</span>
                  <input type="date" min={MIN_DATE} max={MAX_DATE} class="border border-gray-300 px-2 py-1.5 text-sm rounded w-full focus:border-blue-400 focus:ring-0"
                    value={krs.gyldig_fra ?? ""} on:change={(e) => { modalKoerselList[i].koersel.gyldig_fra = e.currentTarget.value; modalKoerselList = modalKoerselList; }} />
                </label>
                <label class="block">
                  <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 block">Gyldig til *</span>
                  <input type="date" min={MIN_DATE} max={MAX_DATE} class="border border-gray-300 px-2 py-1.5 text-sm rounded w-full focus:border-blue-400 focus:ring-0"
                    value={krs.gyldig_til ?? ""} on:change={(e) => { modalKoerselList[i].koersel.gyldig_til = e.currentTarget.value; modalKoerselList = modalKoerselList; }} />
                </label>
                <div></div><div></div>
                <!-- Row 4: Kommentar -->
                <label class="block md:col-start-1 md:col-span-4">
                  <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 block">Kommentar</span>
                  <textarea class={kommentarClass} rows="3"
                    value={krs.kommentar ?? ""} on:change={(e) => { modalKoerselList[i].koersel.kommentar = e.currentTarget.value; modalKoerselList = modalKoerselList; }}></textarea>
                </label>

              {:else if isSRK}
                <!-- Skolerejsekort: Row 2: Transporttid i bus | Antal skift | empty | empty -->
                <label class="block md:col-start-1">
                  <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 block">Transporttid i bus (min.) *</span>
                  <input type="number" min="0" max="500" class="border border-gray-300 px-2 py-1.5 text-sm rounded w-full focus:border-blue-400 focus:ring-0"
                    value={krs.transporttid_i_bus ?? ""} on:change={(e) => { modalKoerselList[i].koersel.transporttid_i_bus = e.currentTarget.value; modalKoerselList = modalKoerselList; }} />
                </label>
                <label class="block">
                  <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 block">Antal skift *</span>
                  <input type="number" min="0" max="10" class="border border-gray-300 px-2 py-1.5 text-sm rounded w-full focus:border-blue-400 focus:ring-0"
                    value={krs.skift_med_bus ?? ""} on:change={(e) => { modalKoerselList[i].koersel.skift_med_bus = e.currentTarget.value; modalKoerselList = modalKoerselList; }} />
                </label>
                <div></div><div></div>
                <!-- Row 3: Gyldig fra | Gyldig til | empty | empty -->
                <label class="block md:col-start-1">
                  <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 block">Gyldig fra *</span>
                  <input type="date" min={MIN_DATE} max={MAX_DATE} class="border border-gray-300 px-2 py-1.5 text-sm rounded w-full focus:border-blue-400 focus:ring-0"
                    value={krs.gyldig_fra ?? ""} on:change={(e) => { modalKoerselList[i].koersel.gyldig_fra = e.currentTarget.value; modalKoerselList = modalKoerselList; }} />
                </label>
                <label class="block">
                  <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 block">Gyldig til *</span>
                  <input type="date" min={MIN_DATE} max={MAX_DATE} class="border border-gray-300 px-2 py-1.5 text-sm rounded w-full focus:border-blue-400 focus:ring-0"
                    value={krs.gyldig_til ?? ""} on:change={(e) => { modalKoerselList[i].koersel.gyldig_til = e.currentTarget.value; modalKoerselList = modalKoerselList; }} />
                </label>
                <div></div><div></div>
                <!-- Row 4: Kommentar -->
                <label class="block md:col-start-1 md:col-span-4">
                  <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 block">Kommentar</span>
                  <textarea class={kommentarClass} rows="3"
                    value={krs.kommentar ?? ""} on:change={(e) => { modalKoerselList[i].koersel.kommentar = e.currentTarget.value; modalKoerselList = modalKoerselList; }}></textarea>
                </label>

              {:else}
                <!-- Default (Skolebus, Gåbus, etc.): Row 2: Gyldig fra | Gyldig til | empty | empty -->
                <label class="block md:col-start-1">
                  <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 block">Gyldig fra *</span>
                  <input type="date" min={MIN_DATE} max={MAX_DATE} class="border border-gray-300 px-2 py-1.5 text-sm rounded w-full focus:border-blue-400 focus:ring-0"
                    value={krs.gyldig_fra ?? ""} on:change={(e) => { modalKoerselList[i].koersel.gyldig_fra = e.currentTarget.value; modalKoerselList = modalKoerselList; }} />
                </label>
                <label class="block">
                  <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 block">Gyldig til *</span>
                  <input type="date" min={MIN_DATE} max={MAX_DATE} class="border border-gray-300 px-2 py-1.5 text-sm rounded w-full focus:border-blue-400 focus:ring-0"
                    value={krs.gyldig_til ?? ""} on:change={(e) => { modalKoerselList[i].koersel.gyldig_til = e.currentTarget.value; modalKoerselList = modalKoerselList; }} />
                </label>
                <div></div><div></div>
                <!-- Row 3: Kommentar -->
                <label class="block md:col-start-1 md:col-span-4">
                  <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 block">Kommentar</span>
                  <textarea class={kommentarClass} rows="3"
                    value={krs.kommentar ?? ""} on:change={(e) => { modalKoerselList[i].koersel.kommentar = e.currentTarget.value; modalKoerselList = modalKoerselList; }}></textarea>
                </label>
              {/if}

            </div>

            {#if entry.distanceError}
              <div class="mt-2 px-3 py-2 text-xs text-red-700 bg-red-50 border border-red-200 rounded">
                {entry.distanceError}
              </div>
            {/if}

          </div>
        {/each}

        <!-- Add entry buttons -->
        <div class="flex gap-3 mt-2">
          <button type="button"
            class="text-sm font-medium text-sky-700 hover:underline"
            on:click={() => { modalKoerselList = [...modalKoerselList, makeEmptyModalEntry()]; }}>
            + Tilføj kørselsrække tom
          </button>
          <button type="button"
            class="text-sm font-medium text-sky-700 hover:underline"
            on:click={() => { modalKoerselList = [...modalKoerselList, makeModalEntryCopy(modalKoerselList[modalKoerselList.length - 1])]; }}>
            + Tilføj kørselsrække fra kopi
          </button>
        </div>
      
      </div>

    {/if}

    <!-- Footer: different buttons per step -->
    {#if modalError}
      <div class="mx-8 mb-4 px-3 py-2 text-sm text-red-700 bg-red-50 border border-red-200 rounded">
        {modalError}
      </div>
    {/if}

    {#if createBevillingStep === 1}
    <div class="flex justify-end gap-3 border-t border-gray-200 px-8 py-5">
      <button type="button"
        class="px-5 py-2 text-sm font-medium border border-gray-300 rounded hover:bg-gray-50 transition-colors"
        on:click={() => dispatch('cancel')}>
        Annullér
      </button>
      <button type="button"
        disabled={!newBevilling.ansoegningstype}
        class="px-5 py-2 text-sm font-medium text-white rounded transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
        style="background-color: #032A42;"
        on:click={handleCreateBevilling}>
        Opret bevilling
      </button>
      <button type="button"
        disabled={!newBevilling.adresse_id}
        class="px-5 py-2 text-sm font-medium bg-green-600 hover:bg-green-700 text-white rounded transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
        on:click={handleGoToStep2}>
        Tilføj Kørselsrækker →
      </button>
    </div>
    {:else}
    <div class="flex items-center justify-between border-t border-gray-200 px-8 py-5">
      <button type="button"
        class="px-4 py-2 text-sm font-medium text-gray-600 hover:text-gray-900 flex items-center gap-1 transition-colors"
        on:click={() => { modalError = null; createBevillingStep = 1; }}>
        ← Tilbage
      </button>
      <div class="flex gap-3">
        <button type="button"
          class="px-5 py-2 text-sm font-medium border border-gray-300 rounded hover:bg-gray-50 transition-colors"
          on:click={() => dispatch('cancel')}>
          Annullér
        </button>
        <button type="button"
          disabled={isCreatingKoerselInModal || !newBevilling.adresse_id}
          class="px-5 py-2 text-sm font-medium bg-green-600 hover:bg-green-700 text-white rounded transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
          on:click={handleCreateBevillingAndKoersel}>
          {isCreatingKoerselInModal ? 'Opretter...' : 'Opret bevilling + kørsel'}
        </button>
      </div>
    </div>
    {/if}

  </div>
</div>