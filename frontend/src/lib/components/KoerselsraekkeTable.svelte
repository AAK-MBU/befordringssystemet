<script lang="ts">
  import { page } from "$app/stores";
  import { MIN_DATE, MAX_DATE, isDateOutOfRange, iDagISO, datoDel } from "$lib/dates";
  import { harEftermiddagForRutetype } from "$lib/rutetype";
  import { formatDanishDate } from "$lib/tableColumnConfig";
  import TagMultiSelect from "$lib/components/TagMultiSelect.svelte";
  import DagePicker from "$lib/components/DagePicker.svelte";
  import {
    availableKoerselstyper as koerselstyperFor,
    isEgenbefordring as typeIsEgenbefordring,
    isKoerselType as typeIsKoersel,
    isSkolerejsekort as typeIsSkolerejsekort,
    isTaxaType as typeIsTaxa,
    labelIsEgenbefordring,
    labelIsSkolerejsekort,
    labelIsTaxa,
  } from "$lib/koerselstype";
  import { afstandFraKoordinater } from "$lib/client/afstand";


  // -----------------------------
  // Props
  // -----------------------------

  export let rows: any[] = [];

  export let lookupOptions: any = {
    tidspunkter: [],
    koerselstyper: [],
    koerselstypeTillaeg: [],
    dage: [],
    rutetyper: []
  };

  export let onCreateKoerselsraekke: (
    updates: any
  ) => Promise<string | null>;

  export let onSaveKoerselsraekke: (
    koerselId: number,
    updates: any
  ) => Promise<string | null>;

  export let onFinalizeKoerselsraekke: (
    koerselId: number
  ) => Promise<string | null>;

  // Coordinates rather than the address text: they come from the LOIS sync on
  // the address itself, so there is nothing to geocode. See $lib/client/afstand.
  export let adresseLat: number | null = null;
  export let adresseLon: number | null = null;
  export let matrikelId: number | null = null;
  export let readonly: boolean = false;

  // Parties on the case, used by the egenbefordring kørselsrække to name the
  // recipient of the kilometre reimbursement.
  export let parter: any[] = [];

  // The bevilling's ansøgningstype. Only "Midlertidig kørsel" restricts which
  // kørselstyper may be chosen; every other type shows the full lookup.
  export let ansoegningstype: string = "";

  // Grey every row out regardless of its own dates, because the bevilling
  // they belong to is Ophørt or Afslag. The per-row Aktiv/Kommende colours
  // describe a date range, which stays "current" on a bevilling that is not —
  // so without this a refused bevilling still shows green rows.
  //
  // Colour only. Editing is unaffected.
  export let bevillingOphoert: boolean = false;

  // Optional — if not provided, the delete button is hidden entirely.
  // Wire this up from the parent page only for users with the correct role.
  export let onDeleteKoerselsraekke: ((koerselId: number) => Promise<string | null>) | undefined = undefined;


  // -----------------------------
  // Distance calculation
  // -----------------------------

  let isCalculatingDistance = false;
  let distanceCalcTarget: 'edit' | 'new' | null = null;  // drives the spinner only
  let distanceErrorFrom: 'edit' | 'new' | null = null;   // persists after finally for display
  let distanceError: string | null = null;

  // Classification lives in $lib/koerselstype so the create modal, this table
  // and BevillingTable can never disagree about what a kørselstype is. These
  // thin wrappers bind the lookup list once so call sites stay readable.
  $: availableKoerselstyper = koerselstyperFor(lookupOptions.koerselstyper, ansoegningstype);

  const isEgenbefordring = (typeId: string | number | null | undefined) =>
    typeIsEgenbefordring(lookupOptions.koerselstyper, typeId);

  const isTaxaType = (typeId: string | number | null | undefined) =>
    typeIsTaxa(lookupOptions.koerselstyper, typeId);

  const isSkolerejsekort = (typeId: string | number | null | undefined) =>
    typeIsSkolerejsekort(lookupOptions.koerselstyper, typeId);

  // "Kørsel til institution" only means something on a kørsel with an
  // afternoon leg: a morning journey takes the child home -> school, and the
  // SFO or klub is where they go afterwards.
  //
  // Answered from the RUTETYPE alone. It used to read tidspunkt first and fall
  // back to rutetype, but two sources for one answer is two rules that can
  // disagree: a række carrying "Morgen" on a "Mellem hjem og skole" rutetype
  // would hide a field the route says belongs there. Rutetype states where the
  // trip starts and ends, so it is the one that can answer — and it is the
  // column that survives, since tidspunkt is being retired.
  //
  // The tidspunkt field is still shown and still saved; nothing decides
  // anything from it.
  const harEftermiddagsTur = (
    rutetypeId: string | number | null | undefined
  ) => harEftermiddagForRutetype(lookupOptions.rutetyper, rutetypeId);

  // Compared as "YYYY-MM-DD" STRINGS, not as Date objects.
  //
  // gyldig_fra is a SQL DATE, so it arrives as "2026-10-02", and
  // `new Date("2026-10-02")` is specified to parse a date-only string as UTC
  // midnight. `today.setHours(0,0,0,0)` gives LOCAL midnight, which in Denmark
  // is one or two hours earlier — so `fra > todayMs` was true for a række
  // starting today, and it showed purple (kommende) until midnight.
  function koerselRowStatus(row: any): 'aktiv' | 'kommende' | 'historisk' {
    const iDag = iDagISO();
    const fra = datoDel(row.gyldig_fra);
    const til = datoDel(row.gyldig_til);

    if (fra <= iDag && iDag <= til) return 'aktiv';
    if (fra > iDag) return 'kommende';
    return 'historisk';
  }

  $: sortedRows = (() => {
    // Was a second copy of koerselRowStatus's comparison, with the same
    // timezone fault — so a række starting today sorted into the kommende
    // group while its own badge said otherwise. Derived from the one function
    // now, so the colour and the grouping cannot disagree again.
    const GRUPPE = { aktiv: 0, kommende: 1, historisk: 2 } as const;

    function group(row: any): number {
      return GRUPPE[koerselRowStatus(row)];
    }

    return [...rows].sort((a, b) => {
      const ga = group(a);
      const gb = group(b);
      if (ga !== gb) return ga - gb;
      const fra_a = new Date(a.gyldig_fra).getTime();
      const fra_b = new Date(b.gyldig_fra).getTime();
      const til_a = new Date(a.gyldig_til).getTime();
      const til_b = new Date(b.gyldig_til).getTime();
      if (ga === 0 && til_a !== til_b) return til_a - til_b; // aktiv: earliest end first
      if (ga === 1 && fra_a !== fra_b) return fra_a - fra_b; // kommende: earliest start first
      if (ga === 2 && til_a !== til_b) return til_b - til_a; // historisk: most recent end first

      // Dates are identical, so Befordring's rutetype order decides.
      // Strictly a TIE-BREAK: it never reorders rækker that cover different
      // periods. The number comes from Rutetype.sorteringsorden via the view
      // rather than from a list here, so this and the letter cannot disagree
      // — see migration 032. The retiring rutetyper have no number and sort
      // last, as does a række with no rutetype at all.
      const ra = a.rutetype_sortering ?? Number.MAX_SAFE_INTEGER;
      const rb = b.rutetype_sortering ?? Number.MAX_SAFE_INTEGER;
      if (ra !== rb) return ra - rb;

      // Last resort, so the order is stable rather than whatever the
      // database happened to return.
      return (a.koersel_id ?? 0) - (b.koersel_id ?? 0);
    });
  })();
  
  const isKoerselType = (typeId: string | number | null | undefined) =>
    typeIsKoersel(lookupOptions.koerselstyper, typeId);

  async function calculateAndFillDistance(
    befordringtypeId: string | number | null,
    target: 'edit' | 'new'
  ) {
    if (!isEgenbefordring(befordringtypeId)) {
      if (target === 'new') {
        updateNewField('bevilget_koereafstand_pr_vej', '');
      } else {
        updateField('bevilget_koereafstand_pr_vej', '');
      }
      return;
    }

    isCalculatingDistance = true;
    distanceCalcTarget = target;
    distanceError = null;
    distanceErrorFrom = null;

    try {
      const { km, error } = await afstandFraKoordinater(adresseLat, adresseLon, matrikelId);

      if (error !== null) {
        distanceError = error;
        distanceErrorFrom = target;
        return;
      }

      // Discard if the user changed the type while we were calculating.
      const currentTypeId = target === 'new'
        ? newKoerselsraekke.befordringstype_id
        : editableKoerselsraekke.befordringstype_id;
      if (Number(currentTypeId) !== Number(befordringtypeId)) return;

      if (target === 'new') {
        updateNewField('bevilget_koereafstand_pr_vej', String(km));
      } else {
        updateField('bevilget_koereafstand_pr_vej', String(km));
      }
    } finally {
      isCalculatingDistance = false;
      distanceCalcTarget = null;
    }
  }


  // -----------------------------
  // Finalize state
  // -----------------------------

  let confirmingFinalizeId: number | null = null;
  let isFinalizing = false;
  let finalizeError: string | null = null;

  async function doFinalize() {
    if (confirmingFinalizeId === null) return;
    isFinalizing = true;
    const id = confirmingFinalizeId;
    confirmingFinalizeId = null;
    const error = await onFinalizeKoerselsraekke(id);
    if (error) finalizeError = error;
    isFinalizing = false;
  }

  let lockedEditRow: any | null = null;

  // -----------------------------
  // Delete state
  // -----------------------------

  let confirmingDeleteKoerselId: number | null = null;
  let isDeleting = false;
  let deleteError: string | null = null;

  // From $page rather than a prop: this component is nested two levels deep and
  // a module-level store would be shared across concurrent SSR requests.
  $: canEdit = $page.data.user?.can_edit ?? false;

  async function doDeleteKoerselsraekke() {
    if (isDeleting || confirmingDeleteKoerselId === null || !onDeleteKoerselsraekke) return;
    isDeleting = true;
    deleteError = null;

    const error = await onDeleteKoerselsraekke(confirmingDeleteKoerselId);

    isDeleting = false;

    // deleteError is rendered inside this dialog, so the dialog has to outlive
    // the failure. Closing it first — as this did — discarded the reason and
    // made a refused delete look exactly like a successful one.
    if (error) {
      deleteError = error;
      return;
    }

    confirmingDeleteKoerselId = null;
  }

  function doLockedEdit() {
    if (!lockedEditRow) return;
    const row = lockedEditRow;
    lockedEditRow = null;
    editingKoerselId = row.koersel_id;
    editableKoerselsraekke = { ...row };
    selectedTillaegIds = parseIds(row.tillaeg_ids);
    selectedDagIds = parseIds(row.dag_ids);
  }


  // -----------------------------
  // Edit state
  // -----------------------------

  let editingKoerselId: number | null = null;
  let editableKoerselsraekke: any = {};
  let editError: string | null = null;

  let selectedTillaegIds: number[] = [];
  let selectedDagIds: number[] = [];


  // -----------------------------
  // Create state
  // -----------------------------

  let isCreating = false;
  let newKoerselsraekke: any = {};
  let createError: string | null = null;

  let newSelectedTillaegIds: number[] = [];
  let newSelectedDagIds: number[] = [];


  // -----------------------------
  // Styling
  // -----------------------------

  const inputClass = "border border-gray-300 px-2 py-1.5 text-sm rounded w-full focus:border-blue-400 focus:ring-0 bg-white";

  // Kommentar is the one free-text field that can hold more than a line. The
  // conversion writes a multi-line note onto kørselsrækker it could not fully
  // interpret (see _klub_note in the conversion RPA), and an <input> would
  // both hide the extra lines and strip them on save — HTML sanitises CR/LF
  // out of a text input's value, so opening the row for editing and saving it
  // unchanged would silently destroy the note.
  const textareaClass = inputClass + " leading-snug resize-y";
  const selectClass = "border border-gray-300 px-2 py-1.5 text-sm rounded w-full focus:border-blue-400 focus:ring-0 bg-white";


  // -----------------------------
  // Small helpers
  // -----------------------------

  // Unanswered means "", null or undefined. Zero is a real answer — 0 skift and
  // 0 minutter are both meaningful — so a plain falsy check would reject them.
  function isBlank(value: unknown): boolean {
    return value === "" || value === null || value === undefined;
  }

  // The Ja/Nej selects carry "true"/"false" strings, while a row loaded from
  // the API carries a real boolean. Unset stays null rather than collapsing to
  // false — "not answered" and "Nej" are different answers.
  function boolOrNull(value: unknown): boolean | null {
    if (value === true || value === "true") return true;
    if (value === false || value === "false") return false;
    return null;
  }

  function numberOrNull(value: string | number | null | undefined) {
    if (value === "" || value === null || value === undefined) {
      return null;
    }

    return Number(value);
  }


  function parseIds(rawValue: string | null | undefined) {
    if (!rawValue) {
      return [];
    }

    return rawValue
      .split(",")
      .map((value) => Number(value))
      .filter((value) => !Number.isNaN(value));
  }


  function getEmptyKoerselsraekke() {
    return {
      tidspunkt_id: "",
      befordringstype_id: "",
      bevilget_koereafstand_pr_vej: "",
      gyldig_fra: "",
      gyldig_til: "",
      taxa_id: "",
      kommentar: "",
      rutetype_id: "",
      koersel_til_institution: "",
      max_minutter_i_transport: "",
      koerselsgodtgoerelse_modtager_id: "",
      koerselsgodtgoerelse_modtager_cpr: "",
      final: false
    };
  }


  // -----------------------------
  // Edit row handling
  // -----------------------------

  function startEdit(row: any) {
    if (row.final) { lockedEditRow = row; return; }
    editingKoerselId = row.koersel_id;
    editableKoerselsraekke = { ...row };

    selectedTillaegIds = parseIds(row.tillaeg_ids);
    selectedDagIds = parseIds(row.dag_ids);
  }


  function cancelEdit() {
    editingKoerselId = null;
    editableKoerselsraekke = {};
    editError = null;

    selectedTillaegIds = [];
    selectedDagIds = [];
  }


  function updateField(key: string, value: any) {
    editableKoerselsraekke = {
      ...editableKoerselsraekke,
      [key]: value
    };
  }


  async function saveEdit(row: any) {
    editError = null;

    // The edit form only checked the dates; the same required fields apply on
    // both sides, so the presence checks come first here too.
    if (!editableKoerselsraekke.gyldig_fra)   { editError = "Gyldig fra skal udfyldes"; return; }
    if (!editableKoerselsraekke.gyldig_til)   { editError = "Gyldig til skal udfyldes"; return; }

    if (isDateOutOfRange(editableKoerselsraekke.gyldig_fra)) {
      editError = "Gyldig fra: Dato er ugyldig — kontrollér årstallet";
      return;
    }
    if (isDateOutOfRange(editableKoerselsraekke.gyldig_til)) {
      editError = "Gyldig til: Dato er ugyldig — kontrollér årstallet";
      return;
    }
    if (editableKoerselsraekke.gyldig_fra && editableKoerselsraekke.gyldig_til &&
        editableKoerselsraekke.gyldig_fra > editableKoerselsraekke.gyldig_til) {
      editError = "Gyldig fra kan ikke være efter gyldig til";
      return;
    }

    const koerselstypeError = validateKoerselstypeFields(
      editableKoerselsraekke,
      editableKoerselsraekke.befordringstype_id,
      selectedDagIds
    );

    if (koerselstypeError) {
      editError = koerselstypeError;
      return;
    }

    const updates = {
      tidspunkt_id: editableKoerselsraekke.tidspunkt_id,
      befordringstype_id: editableKoerselsraekke.befordringstype_id,
      bevilget_koereafstand_pr_vej: numberOrNull(editableKoerselsraekke.bevilget_koereafstand_pr_vej),
      gyldig_fra: editableKoerselsraekke.gyldig_fra,
      gyldig_til: editableKoerselsraekke.gyldig_til,
      taxa_id: editableKoerselsraekke.taxa_id,
      kommentar: editableKoerselsraekke.kommentar,
      rutetype_id: numberOrNull(editableKoerselsraekke.rutetype_id),
      final: false,

      transporttid_i_bus: isSkolerejsekort(editableKoerselsraekke.befordringstype_id) ? numberOrNull(editableKoerselsraekke.transporttid_i_bus) : null,
      skift_med_bus: isSkolerejsekort(editableKoerselsraekke.befordringstype_id) ? numberOrNull(editableKoerselsraekke.skift_med_bus) : null,
      // Only the fields belonging to the chosen kørselstype are sent; the rest
      // are nulled so a value cannot survive a change of type.
      // Nulled when the field does not apply, not merely hidden. Answering
      // "Ja" under Eftermiddag and then switching to Morgen would otherwise
      // leave a morning kørsel claiming it goes to an institution — and the
      // afgørelsesbrev would gain an SFO paragraph about a journey that does
      // not exist.
      koersel_til_institution:
        isTaxaType(editableKoerselsraekke.befordringstype_id) &&
        harEftermiddagsTur(editableKoerselsraekke.rutetype_id)
          ? boolOrNull(editableKoerselsraekke.koersel_til_institution)
          : null,
      max_minutter_i_transport: isTaxaType(editableKoerselsraekke.befordringstype_id) ? numberOrNull(editableKoerselsraekke.max_minutter_i_transport) : null,
      koerselsgodtgoerelse_modtager_id: isEgenbefordring(editableKoerselsraekke.befordringstype_id) ? numberOrNull(editableKoerselsraekke.koerselsgodtgoerelse_modtager_id) : null,
      koerselsgodtgoerelse_modtager_cpr: isEgenbefordring(editableKoerselsraekke.befordringstype_id) ? (editableKoerselsraekke.koerselsgodtgoerelse_modtager_cpr || null) : null,

      tillaeg_ids: isKoerselType(editableKoerselsraekke.befordringstype_id) ? selectedTillaegIds : [],
      dag_ids: selectedDagIds
    };

    const error = await onSaveKoerselsraekke(row.koersel_id, updates);

    if (error) {
      editError = error;
    } else {

      cancelEdit();
    }
  }


  // -----------------------------
  // Create row handling
  // -----------------------------

  function startCreate() {
    isCreating = true;

    // Pre-fill from the latest koerselsraekke (rows[0] after gyldig_til DESC sort).
    // Falls back to empty form if there are no existing rows.
    const source = rows.length > 0 ? rows[0] : null;

    if (source) {
      newKoerselsraekke = {
        tidspunkt_id: source.tidspunkt_id ?? "",
        befordringstype_id: source.befordringstype_id ?? "",
        bevilget_koereafstand_pr_vej: source.bevilget_koereafstand_pr_vej != null
          ? String(source.bevilget_koereafstand_pr_vej)
          : "",
        gyldig_fra: source.gyldig_fra ? String(source.gyldig_fra).slice(0, 10) : "",
        gyldig_til: source.gyldig_til ? String(source.gyldig_til).slice(0, 10) : "",
        taxa_id: source.taxa_id ?? "",
        kommentar: source.kommentar ?? "",
        rutetype_id: source.rutetype_id ?? "",
        koersel_til_institution: source.koersel_til_institution != null ? String(source.koersel_til_institution) : "",
        max_minutter_i_transport: source.max_minutter_i_transport != null ? String(source.max_minutter_i_transport) : "",
        koerselsgodtgoerelse_modtager_id: source.koerselsgodtgoerelse_modtager_id ?? "",
        koerselsgodtgoerelse_modtager_cpr: source.koerselsgodtgoerelse_modtager_cpr ?? "",
        final: false,
      };
      newSelectedTillaegIds = parseIds(source.tillaeg_ids);
      newSelectedDagIds = parseIds(source.dag_ids);
    } else {
      newKoerselsraekke = getEmptyKoerselsraekke();
      newSelectedTillaegIds = [];
      newSelectedDagIds = [];
    }
  }


  function cancelCreate() {
    isCreating = false;
    newKoerselsraekke = {};
    createError = null;

    newSelectedTillaegIds = [];
    newSelectedDagIds = [];
  }


  function updateNewField(key: string, value: any) {
    newKoerselsraekke = {
      ...newKoerselsraekke,
      [key]: value
    };
  }


  // The rules that depend on the chosen kørselstype. Shared by both the edit
  // and the create path so the two can never drift — they did in the code this
  // was ported from, where transporttid and antal skift used two different
  // idioms for the same "unanswered" check.
  function validateKoerselstypeFields(
    values: any,
    befordringstypeId: string | number | null | undefined,
    dagIds: number[]
  ): string | null {
    if (!befordringstypeId) return "Kørselstype skal udfyldes";
    if (dagIds.length === 0) return "Dage skal udfyldes";
    if (!values.rutetype_id) return "Rutetype skal udfyldes";

    if (isEgenbefordring(befordringstypeId)) {
      if (isBlank(values.bevilget_koereafstand_pr_vej)) return "Bevilget km pr. vej skal udfyldes";
      if (isBlank(values.koerselsgodtgoerelse_modtager_id) && isBlank(values.koerselsgodtgoerelse_modtager_cpr)) return "Kørselsgodtgørelse modtager skal udfyldes";
    }

    if (isTaxaType(befordringstypeId)) {
      // Only asked for where it applies — the field is hidden for a
      // morning-only kørsel, and a hidden field cannot be required.
      if (harEftermiddagsTur(values.rutetype_id) && isBlank(values.koersel_til_institution)) {
        return "Kørsel til institution skal udfyldes";
      }
      // max_minutter_i_transport is deliberately NOT required: it is not
      // always known when the kørselsrække is created, the column is nullable
      // and neither the API schema nor the create modal has ever demanded it.
    }

    if (isSkolerejsekort(befordringstypeId)) {
      if (isBlank(values.transporttid_i_bus)) return "Transporttid i bus skal udfyldes";
      if (isBlank(values.skift_med_bus)) return "Antal skift skal udfyldes";
    }

    return null;
  }

  function validateNewKoerselsraekke(): string | null {
    if (!newKoerselsraekke.befordringstype_id) return "Kørselstype skal udfyldes";
    if (!newKoerselsraekke.gyldig_fra) return "Gyldig fra skal udfyldes";
    if (!newKoerselsraekke.gyldig_til) return "Gyldig til skal udfyldes";
    if (isDateOutOfRange(newKoerselsraekke.gyldig_fra)) return "Gyldig fra: Dato er ugyldig — kontrollér årstallet";
    if (isDateOutOfRange(newKoerselsraekke.gyldig_til)) return "Gyldig til: Dato er ugyldig — kontrollér årstallet";
    if (newKoerselsraekke.gyldig_fra > newKoerselsraekke.gyldig_til) return "Gyldig fra kan ikke være efter gyldig til";

    return validateKoerselstypeFields(
      newKoerselsraekke,
      newKoerselsraekke.befordringstype_id,
      newSelectedDagIds
    );
  }


  async function saveNew() {
    createError = null;
    const validationError = validateNewKoerselsraekke();
    if (validationError) {
      createError = validationError;
      return;
    }

    const updates = {
      tidspunkt_id: numberOrNull(newKoerselsraekke.tidspunkt_id),
      befordringstype_id: numberOrNull(newKoerselsraekke.befordringstype_id),
      bevilget_koereafstand_pr_vej: Number(newKoerselsraekke.bevilget_koereafstand_pr_vej),
      gyldig_fra: newKoerselsraekke.gyldig_fra,
      gyldig_til: newKoerselsraekke.gyldig_til,
      taxa_id: newKoerselsraekke.taxa_id || null,
      kommentar: newKoerselsraekke.kommentar || "",
      rutetype_id: numberOrNull(newKoerselsraekke.rutetype_id),
      final: false,

      transporttid_i_bus: isSkolerejsekort(newKoerselsraekke.befordringstype_id) ? numberOrNull(newKoerselsraekke.transporttid_i_bus) : null,
      skift_med_bus: isSkolerejsekort(newKoerselsraekke.befordringstype_id) ? numberOrNull(newKoerselsraekke.skift_med_bus) : null,
      // Only the fields belonging to the chosen kørselstype are sent; the rest
      // are nulled so a value cannot survive a change of type.
      koersel_til_institution:
        isTaxaType(newKoerselsraekke.befordringstype_id) &&
        harEftermiddagsTur(newKoerselsraekke.rutetype_id)
          ? boolOrNull(newKoerselsraekke.koersel_til_institution)
          : null,
      max_minutter_i_transport: isTaxaType(newKoerselsraekke.befordringstype_id) ? numberOrNull(newKoerselsraekke.max_minutter_i_transport) : null,
      koerselsgodtgoerelse_modtager_id: isEgenbefordring(newKoerselsraekke.befordringstype_id) ? numberOrNull(newKoerselsraekke.koerselsgodtgoerelse_modtager_id) : null,
      koerselsgodtgoerelse_modtager_cpr: isEgenbefordring(newKoerselsraekke.befordringstype_id) ? (newKoerselsraekke.koerselsgodtgoerelse_modtager_cpr || null) : null,

      tillaeg_ids: isKoerselType(newKoerselsraekke.befordringstype_id) ? newSelectedTillaegIds : [],
      dag_ids: newSelectedDagIds
    };

    const error = await onCreateKoerselsraekke(updates);

    if (error) {
      createError = error;
    } else {
      cancelCreate();
    }
  }
</script>


<div class="space-y-0">

  {#if finalizeError}
    <div class="mb-3 px-3 py-2 text-sm text-red-700 bg-red-50 border border-red-200 rounded">
      {finalizeError}
    </div>
  {/if}

  <!-- + Ny kørselsrække button / create form — above the rows -->
  {#if !readonly}
  {#if isCreating}

    <div class="mt-2 p-4 bg-white rounded-lg border border-gray-300 shadow-sm">
      <p class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-4">Ny kørselsrække</p>

      <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-x-6 gap-y-4 mb-4">

        <!-- Row 1 col 1: Kørselstype — always fixed -->
        <label class="block">
          <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 block">Kørselstype *</span>
          <select
            class={selectClass}
            value={newKoerselsraekke.befordringstype_id ?? ""}
            on:change={(e) => {
              const id = numberOrNull(e.currentTarget.value);
              updateNewField("befordringstype_id", id);
              if (!isTaxaType(id)) newSelectedTillaegIds = [];
              calculateAndFillDistance(id, 'new');
            }}
          >
            <option value="">Vælg</option>
            {#each availableKoerselstyper as option}
              <option value={option.id}>{option.label}</option>
            {/each}
          </select>
        </label>











        <!-- Row 1, shared: Tidspunkt | Rutetype | Dage -->
        <label class="block">
          <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 block">Tidspunkt</span>
          <select class={selectClass} value={newKoerselsraekke.tidspunkt_id ?? ""} on:change={(e) => updateNewField("tidspunkt_id", numberOrNull(e.currentTarget.value))}>
            <option value="">Vælg</option>
            {#each lookupOptions.tidspunkter ?? [] as option}<option value={option.id}>{option.label}</option>{/each}
          </select>
        </label>
        <label class="block">
          <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 block">Rutetype *</span>
          <select class={selectClass} value={newKoerselsraekke.rutetype_id ?? ""} on:change={(e) => updateNewField("rutetype_id", numberOrNull(e.currentTarget.value))}>
            <option value="">Vælg</option>
            {#each lookupOptions.rutetyper ?? [] as option}<option value={option.id}>{option.label}</option>{/each}
          </select>
        </label>
        <div>
          <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 block">Dage *</span>
          <DagePicker options={lookupOptions.dage ?? []} bind:selected={newSelectedDagIds} />
        </div>
        
        {#if isEgenbefordring(newKoerselsraekke.befordringstype_id)}
          <!-- Egenbefordring: Row 2: Bevilget km | Kørselsgodtgørelse modtager | empty | empty -->
          <label class="block md:col-start-1">
            <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 flex items-center gap-1.5">
              Bevilget km pr. vej *
              {#if isCalculatingDistance && distanceCalcTarget === 'new'}
                <span class="text-blue-500 font-normal normal-case text-[10px]">beregner...</span>
              {/if}
            </span>
            <input type="number" step="0.1"
              class="{inputClass} {isCalculatingDistance && distanceCalcTarget === 'new' ? 'opacity-50' : ''}"
              disabled={isCalculatingDistance && distanceCalcTarget === 'new'}
              value={newKoerselsraekke.bevilget_koereafstand_pr_vej ?? ""}
              on:change={(e) => updateNewField("bevilget_koereafstand_pr_vej", e.currentTarget.value)} />
          </label>
          <label class="block">
            <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 block">Kørselsgodtgørelse modtager *</span>
            <select class={selectClass}
              value={newKoerselsraekke.koerselsgodtgoerelse_modtager_id ? `p:${newKoerselsraekke.koerselsgodtgoerelse_modtager_id}` : newKoerselsraekke.koerselsgodtgoerelse_modtager_cpr ? `f:${newKoerselsraekke.koerselsgodtgoerelse_modtager_cpr}` : ""}
              on:change={(e) => {
                const v = e.currentTarget.value;
                if (!v) { updateNewField("koerselsgodtgoerelse_modtager_id", null); updateNewField("koerselsgodtgoerelse_modtager_cpr", null); }
                else if (v.startsWith("p:")) { updateNewField("koerselsgodtgoerelse_modtager_id", Number(v.slice(2))); updateNewField("koerselsgodtgoerelse_modtager_cpr", null); }
                else if (v.startsWith("f:")) { updateNewField("koerselsgodtgoerelse_modtager_id", null); updateNewField("koerselsgodtgoerelse_modtager_cpr", v.slice(2)); }
              }}>
              <option value="">Vælg</option>
              {#if parter.some((r: any) => r.type === 'foraelder')}
                <optgroup label="Forældre">
                  {#each parter.filter((r: any) => r.type === 'foraelder') as r}<option value="f:{r.cpr_foraelder}">{r.fulde_navn ?? r.cpr_foraelder}{r.relation ? ` (${r.relation})` : ""}</option>{/each}
                </optgroup>
              {/if}
              {#if parter.some((r: any) => r.type === 'part')}
                <optgroup label="Øvrige parter">
                  {#each parter.filter((r: any) => r.type === 'part') as r}<option value="p:{r.part_id}">{r.fulde_navn ?? r.part_id}{r.relation ? ` (${r.relation})` : ""}</option>{/each}
                </optgroup>
              {/if}
              {#if !parter.some((r: any) => r.type)}
                {#each parter as p}<option value="p:{p.part_id}">{p.fulde_navn ?? p.navn ?? p.part_id}{p.relation ? ` (${p.relation})` : ""}</option>{/each}
              {/if}
            </select>
          </label>
          <div></div><div></div>
          <!-- Row 3: Gyldig fra | Gyldig til | empty | empty -->
          <label class="block md:col-start-1">
            <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 block">Gyldig fra *</span>
            <input type="date" class={inputClass} min={MIN_DATE} max={MAX_DATE} value={newKoerselsraekke.gyldig_fra ?? ""} on:change={(e) => updateNewField("gyldig_fra", e.currentTarget.value)} />
          </label>
          <label class="block">
            <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 block">Gyldig til *</span>
            <input type="date" class={inputClass} min={MIN_DATE} max={MAX_DATE} value={newKoerselsraekke.gyldig_til ?? ""} on:change={(e) => updateNewField("gyldig_til", e.currentTarget.value)} />
          </label>
          <div></div><div></div>
          <!-- Row 4: Kommentar full width -->
          <label class="block md:col-start-1 md:col-span-4">
            <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 block">Kommentar</span>
            <textarea class={textareaClass} rows="3" value={newKoerselsraekke.kommentar ?? ""} on:change={(e) => updateNewField("kommentar", e.currentTarget.value)}></textarea>
          </label>

        {:else if isTaxaType(newKoerselsraekke.befordringstype_id)}
          <!-- Taxa: Row 2: Tillæg | Kørsel til institution | Max min | Taxa-ID -->
          <div class="md:col-start-1">
            <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 block">Tillæg</span>
            <TagMultiSelect options={lookupOptions.koerselstypeTillaeg ?? []} bind:selected={newSelectedTillaegIds} placeholder="Tilføj tillæg" />
          </div>
          {#if harEftermiddagsTur(newKoerselsraekke.rutetype_id)}
          <label class="block">
            <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 block">Kørsel til institution *</span>
            <select class={selectClass} value={newKoerselsraekke.koersel_til_institution ?? ""} on:change={(e) => updateNewField("koersel_til_institution", e.currentTarget.value)}>
              <option value="">Vælg</option>
              <option value="true">Ja</option>
              <option value="false">Nej</option>
            </select>
          </label>
          {/if}
          <label class="block">
            <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 block">Max. antal min. i transport</span>
            <input type="number" min="0" max="500" class={inputClass} value={newKoerselsraekke.max_minutter_i_transport ?? ""} on:change={(e) => updateNewField("max_minutter_i_transport", e.currentTarget.value)} />
          </label>
          <label class="block">
            <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 block">Taxa-ID</span>
            <input class={inputClass} value={newKoerselsraekke.taxa_id ?? ""} on:change={(e) => updateNewField("taxa_id", e.currentTarget.value)} />
          </label>
          <!-- Row 3: Gyldig fra | Gyldig til | empty | empty -->
          <label class="block md:col-start-1">
            <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 block">Gyldig fra *</span>
            <input type="date" class={inputClass} min={MIN_DATE} max={MAX_DATE} value={newKoerselsraekke.gyldig_fra ?? ""} on:change={(e) => updateNewField("gyldig_fra", e.currentTarget.value)} />
          </label>
          <label class="block">
            <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 block">Gyldig til *</span>
            <input type="date" class={inputClass} min={MIN_DATE} max={MAX_DATE} value={newKoerselsraekke.gyldig_til ?? ""} on:change={(e) => updateNewField("gyldig_til", e.currentTarget.value)} />
          </label>
          <div></div><div></div>
          <!-- Row 4: Kommentar -->
          <label class="block md:col-start-1 md:col-span-4">
            <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 block">Kommentar</span>
            <textarea class={textareaClass} rows="3" value={newKoerselsraekke.kommentar ?? ""} on:change={(e) => updateNewField("kommentar", e.currentTarget.value)}></textarea>
          </label>

        {:else if isSkolerejsekort(newKoerselsraekke.befordringstype_id)}
          <!-- Skolerejsekort: Row 2: Transporttid i bus | Antal skift | empty | empty -->
          <label class="block md:col-start-1">
            <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 block">Transporttid i bus (min.) *</span>
            <input type="number" min="0" max="500" class={inputClass} value={newKoerselsraekke.transporttid_i_bus ?? ""} on:change={(e) => updateNewField("transporttid_i_bus", e.currentTarget.value)} />
          </label>
          <label class="block">
            <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 block">Antal skift *</span>
            <input type="number" min="0" max="10" class={inputClass} value={newKoerselsraekke.skift_med_bus ?? ""} on:change={(e) => updateNewField("skift_med_bus", e.currentTarget.value)} />
          </label>
          <div></div><div></div>
          <!-- Row 3: Gyldig fra | Gyldig til | empty | empty -->
          <label class="block md:col-start-1">
            <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 block">Gyldig fra *</span>
            <input type="date" class={inputClass} min={MIN_DATE} max={MAX_DATE} value={newKoerselsraekke.gyldig_fra ?? ""} on:change={(e) => updateNewField("gyldig_fra", e.currentTarget.value)} />
          </label>
          <label class="block">
            <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 block">Gyldig til *</span>
            <input type="date" class={inputClass} min={MIN_DATE} max={MAX_DATE} value={newKoerselsraekke.gyldig_til ?? ""} on:change={(e) => updateNewField("gyldig_til", e.currentTarget.value)} />
          </label>
          <div></div><div></div>
          <!-- Row 4: Kommentar -->
          <label class="block md:col-start-1 md:col-span-4">
            <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 block">Kommentar</span>
            <textarea class={textareaClass} rows="3" value={newKoerselsraekke.kommentar ?? ""} on:change={(e) => updateNewField("kommentar", e.currentTarget.value)}></textarea>
          </label>

        {:else}
          <!-- Default (Skolebus, Gåbus, etc.): Row 2: Gyldig fra | Gyldig til | empty | empty -->
          <label class="block md:col-start-1">
            <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 block">Gyldig fra *</span>
            <input type="date" class={inputClass} min={MIN_DATE} max={MAX_DATE} value={newKoerselsraekke.gyldig_fra ?? ""} on:change={(e) => updateNewField("gyldig_fra", e.currentTarget.value)} />
          </label>
          <label class="block">
            <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 block">Gyldig til *</span>
            <input type="date" class={inputClass} min={MIN_DATE} max={MAX_DATE} value={newKoerselsraekke.gyldig_til ?? ""} on:change={(e) => updateNewField("gyldig_til", e.currentTarget.value)} />
          </label>
          <div></div><div></div>
          <!-- Row 3: Kommentar -->
          <label class="block md:col-start-1 md:col-span-4">
            <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 block">Kommentar</span>
            <textarea class={textareaClass} rows="3" value={newKoerselsraekke.kommentar ?? ""} on:change={(e) => updateNewField("kommentar", e.currentTarget.value)}></textarea>
          </label>
        {/if}

      </div>

      {#if distanceError && distanceErrorFrom === 'new'}
        <div class="mb-3 px-3 py-2 text-xs text-red-700 bg-red-50 border border-red-200 rounded">
          {distanceError}
        </div>
      {/if}

      {#if createError}
        <div class="mb-3 px-3 py-2 text-sm text-red-700 bg-red-50 border border-red-200 rounded">
          {createError}
        </div>
      {/if}

      <div class="flex gap-2">
        <button
          type="button"
          class="px-4 py-1.5 text-sm font-medium bg-green-600 hover:bg-green-700 text-white rounded transition-colors"
          on:click={saveNew}
        >
          Gem
        </button>
        <button
          type="button"
          class="px-4 py-1.5 text-sm font-medium border border-gray-300 rounded hover:bg-gray-50 transition-colors"
          on:click={cancelCreate}
        >
          Annullér
        </button>
      </div>
    </div>

  {:else}

    <div class="pt-1 mb-2">
      <button
        type="button"
        disabled={!canEdit}
        class="text-sm font-medium text-sky-700 hover:underline disabled:text-gray-400 disabled:no-underline disabled:cursor-not-allowed"
        on:click={startCreate}
      >
        + Ny kørselsrække
      </button>
    </div>

  {/if}
  {/if}


  <!-- Existing rows -->
  {#if rows.length === 0 && !isCreating}
    <p class="text-sm text-gray-400 py-2">Ingen kørselsrækker endnu.</p>
  {/if}

  {#each sortedRows as row}

    {@const isEditing = editingKoerselId === row.koersel_id}
    {@const rowStatus = koerselRowStatus(row)}

    {#if isEditing}

      <!-- Edit form -->
      <div class="border border-blue-200 rounded-lg p-4 mb-3 bg-blue-50">

        <div class="flex justify-end items-center gap-2 mb-4">
          <button
            type="button"
            class="px-4 py-1.5 text-sm font-medium bg-green-600 hover:bg-green-700 text-white rounded transition-colors"
            on:click={() => saveEdit(row)}
          >
            Gem
          </button>
          <button
            type="button"
            class="px-4 py-1.5 text-sm font-medium border border-gray-300 rounded hover:bg-gray-50 transition-colors"
            on:click={cancelEdit}
          >
            Annullér
          </button>
          {#if onDeleteKoerselsraekke}
            <span class="w-px h-5 bg-blue-200 mx-1"></span>
            <button
              type="button"
              title="Slet kørselsrække"
              disabled={!canEdit}
              class="p-1 text-gray-400 hover:text-red-600 transition-colors disabled:opacity-40 disabled:cursor-not-allowed"
              on:click={() => { confirmingDeleteKoerselId = row.koersel_id; deleteError = null; }}
            >
              <svg class="w-4 h-4" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
              </svg>
            </button>
          {/if}
        </div>

        {#if editError}
          <div class="mb-3 px-3 py-2 text-sm text-red-700 bg-red-50 border border-red-200 rounded">
            {editError}
          </div>
        {/if}

        <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-x-6 gap-y-4 mb-3">

          <!-- Kørselstype — always Row 1, col 1 -->
          <label class="block">
            <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 block">Kørselstype *</span>
            <select
              class={selectClass}
              value={editableKoerselsraekke.befordringstype_id ?? ""}
              on:change={(e) => {
                const id = numberOrNull(e.currentTarget.value);
                updateField("befordringstype_id", id);
                if (!isTaxaType(id)) selectedTillaegIds = [];
                calculateAndFillDistance(id, 'edit');
              }}
            >
              <option value="">Vælg</option>
              {#each availableKoerselstyper as option}
                <option value={option.id}>{option.label}</option>
              {/each}
            </select>
          </label>


          <!-- Row 1, shared: Tidspunkt | Rutetype | Dage -->
          <label class="block">
            <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 block">Tidspunkt</span>
            <select class={selectClass} value={editableKoerselsraekke.tidspunkt_id ?? ""} on:change={(e) => updateField("tidspunkt_id", numberOrNull(e.currentTarget.value))}>
              <option value="">Vælg</option>
              {#each lookupOptions.tidspunkter ?? [] as option}<option value={option.id}>{option.label}</option>{/each}
            </select>
          </label>
          <label class="block">
            <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 block">Rutetype *</span>
            <select class={selectClass} value={editableKoerselsraekke.rutetype_id ?? ""} on:change={(e) => updateField("rutetype_id", numberOrNull(e.currentTarget.value))}>
              <option value="">Vælg</option>
              {#each lookupOptions.rutetyper ?? [] as option}<option value={option.id}>{option.label}</option>{/each}
            </select>
          </label>
          <div>
            <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 block">Dage *</span>
            <DagePicker options={lookupOptions.dage ?? []} bind:selected={selectedDagIds} />
          </div>

          {#if isEgenbefordring(editableKoerselsraekke.befordringstype_id)}
            <!-- Egenbefordring: Row 2: Bevilget km | Kørselsgodtgørelse modtager | empty | empty -->
            <label class="block md:col-start-1">
              <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 flex items-center gap-1.5">
                Bevilget km pr. vej *
                {#if isCalculatingDistance && distanceCalcTarget === 'edit'}
                  <span class="text-blue-500 font-normal normal-case text-[10px]">beregner...</span>
                {/if}
              </span>
              <input
                type="number"
                step="0.1"
                class="{inputClass} {isCalculatingDistance && distanceCalcTarget === 'edit' ? 'opacity-50' : ''}"
                disabled={isCalculatingDistance && distanceCalcTarget === 'edit'}
                value={editableKoerselsraekke.bevilget_koereafstand_pr_vej ?? ""}
                on:change={(e) => updateField("bevilget_koereafstand_pr_vej", e.currentTarget.value)}
              />
            </label>
            <label class="block">
              <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 block">Kørselsgodtgørelse modtager *</span>
              <select class={selectClass}
                value={editableKoerselsraekke.koerselsgodtgoerelse_modtager_id ? `p:${editableKoerselsraekke.koerselsgodtgoerelse_modtager_id}` : editableKoerselsraekke.koerselsgodtgoerelse_modtager_cpr ? `f:${editableKoerselsraekke.koerselsgodtgoerelse_modtager_cpr}` : ""
}
                on:change={(e) => {
                  const v = e.currentTarget.value;
                  if (!v) { updateField("koerselsgodtgoerelse_modtager_id", null); updateField("koerselsgodtgoerelse_modtager_cpr", null); }
                  else if (v.startsWith("p:")) { updateField("koerselsgodtgoerelse_modtager_id", Number(v.slice(2))); updateField("koerselsgodtgoerelse_modtager_cpr", null); }
                  else if (v.startsWith("f:")) { updateField("koerselsgodtgoerelse_modtager_id", null); updateField("koerselsgodtgoerelse_modtager_cpr", v.slice(2)); }
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
              <input type="date" class={inputClass} min={MIN_DATE} max={MAX_DATE} value={editableKoerselsraekke.gyldig_fra ?? ""} on:change={(e) => updateField("gyldig_fra", e.currentTarget.value)} />
            </label>
            <label class="block">
              <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 block">Gyldig til *</span>
              <input type="date" class={inputClass} min={MIN_DATE} max={MAX_DATE} value={editableKoerselsraekke.gyldig_til ?? ""} on:change={(e) => updateField("gyldig_til", e.currentTarget.value)} />
            </label>
            <div></div><div></div>
            <!-- Row 4: Kommentar -->
            <label class="block md:col-start-1 md:col-span-4">
              <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 block">Kommentar</span>
              <textarea class={textareaClass} rows="3" value={editableKoerselsraekke.kommentar ?? ""} on:change={(e) => updateField("kommentar", e.currentTarget.value)}></textarea>
            </label>

          {:else if isTaxaType(editableKoerselsraekke.befordringstype_id)}
            <!-- Taxa (Skåne, Solo, Variabel, Rute): Row 2: Tillæg | Kørsel til institution | Max. antal min. i transport | Taxa-ID -->
            <div class="md:col-start-1">
              <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 block">Tillæg</span>
              <TagMultiSelect options={lookupOptions.koerselstypeTillaeg ?? []} bind:selected={selectedTillaegIds} placeholder="Tilføj tillæg" />
            </div>
            {#if harEftermiddagsTur(editableKoerselsraekke.rutetype_id)}
            <label class="block">
              <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 block">Kørsel til institution *</span>
              <select class={selectClass} value={editableKoerselsraekke.koersel_til_institution != null ? String(editableKoerselsraekke.koersel_til_institution) : ""} on:change={(e) => updateField("koersel_til_institution", e.currentTarget.value)}>
                <option value="">Vælg</option>
                <option value="true">Ja</option>
                <option value="false">Nej</option>
              </select>
            </label>
            {/if}
            <label class="block">
              <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 block">Max. antal min. i transport</span>
              <input type="number" min="0" max="500" class={inputClass} value={editableKoerselsraekke.max_minutter_i_transport ?? ""} on:change={(e) => updateField("max_minutter_i_transport", e.currentTarget.value)} />
            </label>
            <label class="block">
              <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 block">Taxa-ID</span>
              <input class={inputClass} value={editableKoerselsraekke.taxa_id ?? ""} on:change={(e) => updateField("taxa_id", e.currentTarget.value)} />
            </label>
            <!-- Row 3: Gyldig fra | Gyldig til | empty | empty -->
            <label class="block md:col-start-1">
              <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 block">Gyldig fra *</span>
              <input type="date" class={inputClass} min={MIN_DATE} max={MAX_DATE} value={editableKoerselsraekke.gyldig_fra ?? ""} on:change={(e) => updateField("gyldig_fra", e.currentTarget.value)} />
            </label>
            <label class="block">
              <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 block">Gyldig til *</span>
              <input type="date" class={inputClass} min={MIN_DATE} max={MAX_DATE} value={editableKoerselsraekke.gyldig_til ?? ""} on:change={(e) => updateField("gyldig_til", e.currentTarget.value)} />
            </label>
            <div></div><div></div>
            <!-- Row 4: Kommentar -->
            <label class="block md:col-start-1 md:col-span-4">
              <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 block">Kommentar</span>
              <textarea class={textareaClass} rows="3" value={editableKoerselsraekke.kommentar ?? ""} on:change={(e) => updateField("kommentar", e.currentTarget.value)}></textarea>
            </label>

          {:else if isSkolerejsekort(editableKoerselsraekke.befordringstype_id)}
            <!-- Skolerejsekort: Row 2: Transporttid i bus | Antal skift | empty | empty -->
            <label class="block md:col-start-1">
              <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 block">Transporttid i bus (min.) *</span>
              <input type="number" min="0" max="500" class={inputClass} value={editableKoerselsraekke.transporttid_i_bus ?? ""} on:change={(e) => updateField("transporttid_i_bus", e.currentTarget.value)} />
            </label>
            <label class="block">
              <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 block">Antal skift *</span>
              <input type="number" min="0" max="10" class={inputClass} value={editableKoerselsraekke.skift_med_bus ?? ""} on:change={(e) => updateField("skift_med_bus", e.currentTarget.value)} />
            </label>
            <div></div><div></div>
            <!-- Row 3: Gyldig fra | Gyldig til | empty | empty -->
            <label class="block md:col-start-1">
              <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 block">Gyldig fra *</span>
              <input type="date" class={inputClass} min={MIN_DATE} max={MAX_DATE} value={editableKoerselsraekke.gyldig_fra ?? ""} on:change={(e) => updateField("gyldig_fra", e.currentTarget.value)} />
            </label>
            <label class="block">
              <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 block">Gyldig til *</span>
              <input type="date" class={inputClass} min={MIN_DATE} max={MAX_DATE} value={editableKoerselsraekke.gyldig_til ?? ""} on:change={(e) => updateField("gyldig_til", e.currentTarget.value)} />
            </label>
            <div></div><div></div>
            <!-- Row 4: Kommentar -->
            <label class="block md:col-start-1 md:col-span-4">
              <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 block">Kommentar</span>
              <textarea class={textareaClass} rows="3" value={editableKoerselsraekke.kommentar ?? ""} on:change={(e) => updateField("kommentar", e.currentTarget.value)}></textarea>
            </label>

          {:else}
            <!-- Default (Skolebus, Gåbus, etc.): Row 2: Gyldig fra | Gyldig til | empty | empty -->
            <label class="block md:col-start-1">
              <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 block">Gyldig fra *</span>
              <input type="date" class={inputClass} min={MIN_DATE} max={MAX_DATE} value={editableKoerselsraekke.gyldig_fra ?? ""} on:change={(e) => updateField("gyldig_fra", e.currentTarget.value)} />
            </label>
            <label class="block">
              <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 block">Gyldig til *</span>
              <input type="date" class={inputClass} min={MIN_DATE} max={MAX_DATE} value={editableKoerselsraekke.gyldig_til ?? ""} on:change={(e) => updateField("gyldig_til", e.currentTarget.value)} />
            </label>
            <div></div><div></div>
            <!-- Row 3: Kommentar -->
            <label class="block md:col-start-1 md:col-span-4">
              <span class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1 block">Kommentar</span>
              <textarea class={textareaClass} rows="3" value={editableKoerselsraekke.kommentar ?? ""} on:change={(e) => updateField("kommentar", e.currentTarget.value)}></textarea>
            </label>
          {/if}

        </div>

        {#if distanceError && distanceErrorFrom === 'edit'}
          <div class="mb-3 px-3 py-2 text-xs text-red-700 bg-red-50 border border-red-200 rounded">
            {distanceError}
          </div>
        {/if}

      </div>

    {:else}
    
      {@const isEgb = labelIsEgenbefordring(row.befordringstype_tekst)}
      {@const isTxa = labelIsTaxa(row.befordringstype_tekst)}
      {@const isSRK = labelIsSkolerejsekort(row.befordringstype_tekst)}

      <!-- Labeled field grid view (matches the bevilling header card) -->
      <div class="mb-2 rounded-lg border shadow-sm overflow-hidden
        {bevillingOphoert || rowStatus === 'historisk' ? 'bg-gray-50 border-gray-200' : rowStatus === 'aktiv' ? 'bg-green-50 border-green-200' : 'bg-purple-50 border-purple-200'}"
        style="border-left: 4px solid {bevillingOphoert || rowStatus === 'historisk' ? '#9ca3af' : rowStatus === 'aktiv' ? '#16a34a' : '#9333ea'};">

        <div class="flex items-start justify-between gap-4 px-4 py-4">

          <div class="flex-1 min-w-0 grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-x-6 gap-y-4">

            <!-- Row 1, shared: Kørselstype | Tidspunkt | Rutetype | Dage -->
            <div>
              <p class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1">Kørselstype</p>
              <p class="text-sm font-semibold text-gray-800 break-words">{row.befordringstype_tekst ?? "—"}</p>
            </div>
            <div>
              <p class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1">Tidspunkt</p>
              <p class="text-sm text-gray-800 break-words">{row.tidspunkt_tekst ?? "—"}</p>
            </div>
            <div>
              <p class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1">Rutetype</p>
              <p class="text-sm text-gray-800 break-words">{row.rutetype_tekst ?? "—"}</p>
            </div>
            <div>
              <p class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1">Dage</p>
              <p class="text-sm text-gray-800 break-words">{row.dage ?? "—"}</p>
            </div>

            {#if isEgb}
              <!-- Egenbefordring: Row 2: Bevilget km | Kørselsgodtgørelse modtager | empty | empty -->
              <div>
                <p class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1">Bevilget km pr. vej</p>
                <p class="text-sm text-gray-800">{row.bevilget_koereafstand_pr_vej != null ? String(parseFloat(row.bevilget_koereafstand_pr_vej)).replace('.', ',') : "—"}</p>
              </div>
              <div>
                <p class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1">Kørselsgodtgørelse modtager</p>
                <p class="text-sm text-gray-800 break-words">
                  {#if row.koerselsgodtgoerelse_modtager_id}
                    {#each [parter.find((r: any) => r.type === 'part' && r.part_id === row.koerselsgodtgoerelse_modtager_id)] as modtager}
                      {modtager ? (modtager.fulde_navn ?? modtager.part_id) + (modtager.relation ? ` (${modtager.relation})` : '') : '—'}
                    {/each}
                  {:else if row.koerselsgodtgoerelse_modtager_cpr}
                    {#each [parter.find((r: any) => r.type === 'foraelder' && r.cpr_foraelder === row.koerselsgodtgoerelse_modtager_cpr)] as modtager}
                      {modtager ? (modtager.fulde_navn ?? modtager.cpr_foraelder) + (modtager.relation ? ` (${modtager.relation})` : '') : '—'}
                    {/each}
                  {:else}
                    —
                  {/if}
                </p>
              </div>
              <div></div><div></div>
              <!-- Row 3: Gyldig fra | Gyldig til | empty | empty -->
              <div>
                <p class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1">Gyldig fra</p>
                <p class="text-sm text-gray-800">{formatDanishDate(row.gyldig_fra)}</p>
              </div>
              <div>
                <p class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1">Gyldig til</p>
                <p class="text-sm text-gray-800">{formatDanishDate(row.gyldig_til)}</p>
              </div>
              <div></div><div></div>
              <!-- Row 4: Kommentar -->
              <div class="md:col-span-4">
                <p class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1">Kommentar</p>
                <p class="text-sm text-gray-800 italic break-words whitespace-pre-line">{row.kommentar ?? "—"}</p>
              </div>

            {:else if isTxa}
              <!-- Taxa: Row 2: Tillæg | Kørsel til institution | Max min | Taxa-ID -->
              <div>
                <p class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1">Tillæg</p>
                <p class="text-sm text-gray-800 break-words">{row.tillaeg_tekst ?? "—"}</p>
              </div>
              <div>
                <p class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1">Kørsel til institution</p>
                <p class="text-sm text-gray-800">{row.koersel_til_institution === true ? 'Ja' : row.koersel_til_institution === false ? 'Nej' : '—'}</p>
              </div>
              <div>
                <p class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1">Max. antal min. i transport</p>
                <p class="text-sm text-gray-800">{row.max_minutter_i_transport ?? "—"}</p>
              </div>
              <div>
                <p class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1">Taxa-ID</p>
                <p class="text-sm text-gray-800 break-words">{row.taxa_id || "—"}</p>
              </div>
              <!-- Row 3: Gyldig fra | Gyldig til | empty | empty -->
              <div>
                <p class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1">Gyldig fra</p>
                <p class="text-sm text-gray-800">{formatDanishDate(row.gyldig_fra)}</p>
              </div>
              <div>
                <p class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1">Gyldig til</p>
                <p class="text-sm text-gray-800">{formatDanishDate(row.gyldig_til)}</p>
              </div>
              <div></div><div></div>
              <!-- Row 4: Kommentar -->
              <div class="md:col-span-4">         
                <p class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1">Kommentar</p>
                <p class="text-sm text-gray-800 italic break-words whitespace-pre-line">{row.kommentar ?? "—"}</p>
              </div>

            {:else if isSRK}
              <!-- Skolerejsekort: Row 2: Transporttid i bus | Antal skift | empty | empty -->
              <div>
                <p class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1">Transporttid i bus (min.)</p>
                <p class="text-sm text-gray-800">{row.transporttid_i_bus ?? "—"}</p>
              </div>
              <div>
                <p class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1">Antal skift</p>
                <p class="text-sm text-gray-800">{row.skift_med_bus ?? "—"}</p>
              </div>
              <div></div><div></div>
              <!-- Row 3: Gyldig fra | Gyldig til | empty | empty -->
              <div>
                <p class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1">Gyldig fra</p>
                <p class="text-sm text-gray-800">{formatDanishDate(row.gyldig_fra)}</p>
              </div>
              <div>
                <p class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1">Gyldig til</p>
                <p class="text-sm text-gray-800">{formatDanishDate(row.gyldig_til)}</p>
              </div>
              <div></div><div></div>
              <!-- Row 4: Kommentar -->
              <div class="md:col-span-4">
                <p class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1">Kommentar</p>
                <p class="text-sm text-gray-800 italic break-words whitespace-pre-line">{row.kommentar ?? "—"}</p>
              </div>

            {:else}
              <!-- Default (Skolebus, Gåbus, etc.): Row 2: Gyldig fra | Gyldig til | empty | empty -->
              <div>
                <p class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1">Gyldig fra</p>
                <p class="text-sm text-gray-800">{formatDanishDate(row.gyldig_fra)}</p>
              </div>
              <div>
                <p class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1">Gyldig til</p>
                <p class="text-sm text-gray-800">{formatDanishDate(row.gyldig_til)}</p>
              </div>
              <div></div><div></div>
              <!-- Row 3: Kommentar -->
              <div class="md:col-span-4">
                <p class="text-[10px] font-bold uppercase tracking-wider text-gray-500 mb-1">Kommentar</p>
                <p class="text-sm text-gray-800 italic break-words whitespace-pre-line">{row.kommentar ?? "—"}</p>
              </div>
            {/if}

          </div>

          <!-- Handlinger -->
          <div class="flex items-center gap-2 shrink-0">

            {#if row.final}
              <!-- Locked state: redigér + closed lock icon (mirrors unlocked layout) -->
              {#if !readonly}
                <button
                  type="button"
                  disabled={!canEdit}
                  class="px-3 py-1 text-xs border border-gray-300 rounded hover:bg-gray-50 transition-colors disabled:opacity-40 disabled:cursor-not-allowed"
                  on:click={() => startEdit(row)}
                >
                  Redigér
                </button>
              {/if}
              <span title="Låst" class="p-1 text-gray-400 cursor-default">
                <svg class="w-4 h-4" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
                </svg>
              </span>
            {:else if !readonly}
              <!-- Unlocked state: redigér + lock button -->
              <button
                type="button"
                disabled={!canEdit}
                class="px-3 py-1 text-xs border border-gray-300 rounded hover:bg-gray-50 transition-colors disabled:opacity-40 disabled:cursor-not-allowed"
                on:click={() => startEdit(row)}
              >
                Redigér
              </button>
              <button
                type="button"
                title="Lås kørselsrække"
                class="p-1 text-gray-400 hover:text-gray-600 transition-colors"
                on:click={() => confirmingFinalizeId = row.koersel_id}
              >
                <!-- lock-open icon -->
                <svg class="w-4 h-4" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M8 11V7a4 4 0 118 0m-4 8v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2z" />
                </svg>
              </button>
            {/if}

          </div>

        </div>

      </div>

    {/if}

  {/each}



</div>


<svelte:window on:keydown={(e) => {
  if (e.key === 'Escape') {
    if (confirmingFinalizeId !== null) confirmingFinalizeId = null;
    if (lockedEditRow !== null) lockedEditRow = null;
    if (confirmingDeleteKoerselId !== null) confirmingDeleteKoerselId = null;
  }
}} />

<!-- Finalize confirmation modal -->
{#if confirmingFinalizeId !== null}
  <!-- Backdrop is non-dismissing: close only via Escape or the Annullér button. -->
  <div
    class="fixed inset-0 z-50 flex items-center justify-center bg-black/40"
    role="presentation"
  >
    <div
      class="w-[420px] bg-white rounded-lg shadow-2xl"
      role="dialog"
      aria-modal="true"
      tabindex="-1"
    >
      <div class="px-6 py-5 border-b border-gray-200">
        <div class="flex items-center gap-3">
          <div class="w-9 h-9 rounded-full bg-amber-100 flex items-center justify-center shrink-0">
            <svg class="w-5 h-5 text-amber-600" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
            </svg>
          </div>
          <div>
            <h2 class="text-base font-semibold text-gray-900">Lås kørselsrække</h2>
            <p class="text-xs text-gray-500 mt-0.5">Kan genåbnes ved behov</p>
          </div>
        </div>
      </div>

      <div class="px-6 py-5">
        <p class="text-sm text-gray-700">
          Kørselsrækken vil blive markeret som <strong>låst</strong> og kan kun redigeres efter bekræftelse.
        </p>
        <p class="text-sm text-gray-500 mt-2">
          Er du sikker på, at du vil låse denne kørselsrække?
        </p>
      </div>

      <div class="flex justify-end gap-3 px-6 py-4 border-t border-gray-200 bg-gray-50 rounded-b-lg">
        <button
          type="button"
          class="px-4 py-2 text-sm font-medium border border-gray-300 rounded hover:bg-white transition-colors"
          on:click={() => confirmingFinalizeId = null}
        >
          Annullér
        </button>
        <button
          type="button"
          class="px-4 py-2 text-sm font-medium bg-amber-600 hover:bg-amber-700 text-white rounded transition-colors disabled:opacity-50"
          disabled={isFinalizing}
          on:click={doFinalize}
        >
          {isFinalizing ? 'Låser...' : 'Lås kørselsrække'}
        </button>
      </div>
    </div>
  </div>
{/if}


<!-- Locked edit confirmation popup -->
{#if lockedEditRow !== null}
  <div
    class="fixed inset-0 z-50 flex items-center justify-center bg-black/40"
    role="presentation"
  >
    <div
      class="w-[420px] bg-white rounded-lg shadow-2xl"
      role="dialog"
      aria-modal="true"
      tabindex="-1"
    >
      <div class="px-6 py-5 border-b border-gray-200">
        <div class="flex items-center gap-3">
          <div class="w-9 h-9 rounded-full bg-amber-100 flex items-center justify-center shrink-0">
            <svg class="w-5 h-5 text-amber-600" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
            </svg>
          </div>
          <div>
            <h2 class="text-base font-semibold text-gray-900">Rediger låst kørselsrække</h2>
            <p class="text-xs text-gray-500 mt-0.5">Kræver bekræftelse</p>
          </div>
        </div>
      </div>

      <div class="px-6 py-5">
        <p class="text-sm text-gray-700">
          Kørselsrækken er låst. <strong>Husk at sende nyt brev</strong> når du har redigeret i en låst kørselsrække.
        </p>
        <p class="text-sm text-gray-500 mt-2">
          Er du sikker på, at du vil redigere denne kørselsrække?
        </p>
      </div>

      <div class="flex justify-end gap-3 px-6 py-4 border-t border-gray-200 bg-gray-50 rounded-b-lg">
        <button
          type="button"
          class="px-4 py-2 text-sm font-medium border border-gray-300 rounded hover:bg-white transition-colors"
          on:click={() => lockedEditRow = null}
        >
          Annullér
        </button>
        <button
          type="button"
          class="px-4 py-2 text-sm font-medium bg-amber-600 hover:bg-amber-700 text-white rounded transition-colors"
          on:click={doLockedEdit}
        >
          Redigér
        </button>
      </div>
    </div>
  </div>
{/if}



<!-- Delete kørselsrække confirmation modal -->
{#if confirmingDeleteKoerselId !== null}
  <div
    class="fixed inset-0 z-50 flex items-center justify-center bg-black/40"
    role="presentation"
  >
    <div
      class="w-[420px] bg-white rounded-lg shadow-2xl"
      role="dialog"
      aria-modal="true"
      tabindex="-1"
    >
      <div class="px-6 py-5 border-b border-gray-200">
        <div class="flex items-center gap-3">
          <div class="w-9 h-9 rounded-full bg-red-100 flex items-center justify-center shrink-0">
            <svg class="w-5 h-5 text-red-600" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6
v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
            </svg>
          </div>
          <div>
            <h3 class="text-sm font-semibold text-gray-900">Slet kørselsrække</h3>
            <p class="text-xs text-gray-500 mt-0.5">Kørselsrække #{confirmingDeleteKoerselId}</p>
          </div>
        </div>
      </div>
      <div class="px-6 py-4">
        <p class="text-sm text-gray-700">
          Er du sikker på, at du vil slette denne kørselsrække?
          Den vil blive skjult for brugere, men bevares i databasen.
        </p>
        {#if deleteError}
          <p class="mt-3 text-sm text-red-600 bg-red-50 border border-red-200 rounded px-3 py-2">{deleteError}</p>
        {/if}
      </div>
      <div class="flex justify-end gap-3 px-6 py-4 border-t border-gray-200 bg-gray-50 rounded-b-lg">
        <button
          type="button"
          class="px-4 py-2 text-sm font-medium border border-gray-300 rounded hover:bg-gray-100 transition-colors"
          on:click={() => confirmingDeleteKoerselId = null}
        >
          Annullér
        </button>
        <button
          type="button"
          disabled={isDeleting}
          class="px-4 py-2 text-sm font-medium bg-red-600 hover:bg-red-700 text-white rounded transition-colors disabled:opacity-50"
          on:click={doDeleteKoerselsraekke}
        >
          {isDeleting ? "Sletter…" : "Slet kørselsrække"}
        </button>
      </div>
    </div>
  </div>
{/if}