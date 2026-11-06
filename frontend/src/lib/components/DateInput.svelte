<script lang="ts">
  /**
   * A date field that shows ISO week numbers in its calendar.
   *
   * Drop-in replacement for `<input type="date">`. The reason it exists is that
   * a native date input opens the BROWSER's calendar — Chrome's, Firefox's,
   * Edge's own widget — which is not part of the page. No CSS, no script and no
   * attribute reaches into it, and none of them render week numbers. The only
   * way to show a week number is to stop using the native picker, so this wraps
   * flowbite-datepicker (already a dependency, previously unused) on a plain
   * text input instead.
   *
   * Befordring's reason for wanting them: fixing an ophørsdato against a school
   * holiday weeks or months out, without a separate feriekalender open beside
   * the screen.
   *
   * The week numbers are ISO-8601 — Monday start, week 1 is the week containing
   * 4 January — which is the library's own `getWeek`, not something computed
   * here. That matters more than it looks: a naive "week of year" count drifts
   * around New Year, which is exactly where juleferie sits.
   *
   * CONTRACT, and the thing to preserve when editing this:
   *
   *   `value` is always an ISO "YYYY-MM-DD" string, or "". The visible text is
   *   Danish dd/mm/yyyy. Everything downstream — the API payloads, isValidDate
   *   and isDateOutOfRange in $lib/dates, the lexicographic date comparisons
   *   all over the tables — depends on the ISO form, and none of it ever sees
   *   the displayed text.
   */

  import { createEventDispatcher, onDestroy, onMount } from "svelte";
  import Datepicker from "flowbite-datepicker/Datepicker";
  import { MAX_DATE, MIN_DATE } from "$lib/dates";

  export let value: string | null | undefined = "";
  export let min: string = MIN_DATE;
  export let max: string = MAX_DATE;
  export let disabled: boolean = false;
  export let required: boolean = false;
  export let id: string | undefined = undefined;
  export let name: string | undefined = undefined;
  export let placeholder: string = "dd/mm-åååå";
  export let ariaLabel: string | undefined = undefined;

  // `class` is reserved, so it is taken in under another name and re-exported.
  // Every call site passes its own Tailwind classes; this component imposes no
  // styling of its own beyond what it is given.
  let klass: string = "";
  export { klass as class };

  const dispatch = createEventDispatcher<{ change: string }>();

  /**
   * The Danish locale, inlined rather than imported.
   *
   * flowbite-datepicker ships `js/i18n/locales/da.js`, but `js/` is not in the
   * package's `exports` map, so importing it by subpath is not guaranteed to
   * resolve. It is twelve lines; copying them is cheaper than depending on an
   * unexported path.
   *
   * `weekStart: 1` is not cosmetic — ISO week numbers only line up against a
   * Monday-start grid.
   */
  const DA_LOCALE = {
    da: {
      days: ["Søndag", "Mandag", "Tirsdag", "Onsdag", "Torsdag", "Fredag", "Lørdag"],
      daysShort: ["Søn", "Man", "Tir", "Ons", "Tor", "Fre", "Lør"],
      daysMin: ["Sø", "Ma", "Ti", "On", "To", "Fr", "Lø"],
      months: [
        "Januar", "Februar", "Marts", "April", "Maj", "Juni",
        "Juli", "August", "September", "Oktober", "November", "December",
      ],
      monthsShort: [
        "Jan", "Feb", "Mar", "Apr", "Maj", "Jun",
        "Jul", "Aug", "Sep", "Okt", "Nov", "Dec",
      ],
      today: "I dag",
      clear: "Ryd",
      format: "dd/mm/yyyy",
      weekStart: 1,
      monthsTitle: "Måneder",
    },
  };

  let input: HTMLInputElement;
  let picker: Datepicker | null = null;

  /**
   * Breaks the feedback loop. `setDate()` fires `changeDate`, whose handler
   * writes to `value`, whose reactive statement calls `setDate()` again. The
   * flag marks the writes this component made itself so they are not echoed
   * back out as user edits.
   */
  let syncing = false;

  /** A Date as local "YYYY-MM-DD". Local, not UTC: see iDagISO in $lib/dates. */
  function toISO(date: Date | undefined | null): string {
    if (!date || Number.isNaN(date.getTime())) {
      return "";
    }

    return [
      date.getFullYear(),
      String(date.getMonth() + 1).padStart(2, "0"),
      String(date.getDate()).padStart(2, "0"),
    ].join("-");
  }

  function onPickerChange() {
    if (syncing || !picker) {
      return;
    }

    const next = toISO(picker.getDate());

    if (next === (value ?? "")) {
      return;
    }

    value = next;
    dispatch("change", next);
  }

  /** Push the current `value` into the picker without echoing it back out. */
  function syncFromValue() {
    if (!picker) {
      return;
    }

    const current = toISO(picker.getDate());
    const wanted = value ?? "";

    if (current === wanted) {
      return;
    }

    syncing = true;

    try {
      // render: true so the calendar jumps to the month it is now showing —
      // otherwise loading a row into an edit form leaves the picker opening on
      // whatever month it last displayed. autohide is forced off because the
      // picker's own default is on, and a programmatic sync must never close a
      // calendar the user has open.
      if (wanted) {
        picker.setDate(wanted, { render: true, autohide: false });
      } else {
        picker.setDate({ clear: true, render: true, autohide: false });
      }
    } finally {
      syncing = false;
    }
  }

  onMount(() => {
    Object.assign(Datepicker.locales, DA_LOCALE);

    picker = new Datepicker(input, {
      language: "da",
      format: "dd/mm/yyyy",
      // The entire point of this component.
      calendarWeeks: true,
      weekStart: 1,
      autohide: true,
      todayBtn: true,
      todayBtnMode: 1,
      todayHighlight: true,
      clearBtn: true,
      // Same bounds the native inputs carried as min/max. They constrain the
      // calendar only; $lib/dates still guards the submitted value, because a
      // pasted or typed string reaches `value` without the picker's say-so.
      minDate: min,
      maxDate: max,
      orientation: "bottom auto",
    });

    // The dropdown ships with `z-50`, which ties with the modals in this app
    // (CreateLetterModal is z-50). The picker is appended to <body> when this
    // component mounts, so against a modal opened later it loses the tie on DOM
    // order and renders behind it. One step clear of the tie.
    if (picker?.picker?.element) {
      picker.picker.element.style.zIndex = "60";
    }

    input.addEventListener("changeDate", onPickerChange);

    syncFromValue();
  });

  onDestroy(() => {
    if (!picker) {
      return;
    }

    input.removeEventListener("changeDate", onPickerChange);
    picker.destroy();
    picker = null;
  });

  // Keep the field in step when the parent replaces `value` — loading a row
  // into an edit form, resetting a modal, clearing a filter.
  $: if (picker && value !== undefined) {
    syncFromValue();
  }

  // Bounds are props, so a caller can narrow them per field.
  $: if (picker) {
    picker.setOptions({ minDate: min, maxDate: max });
  }
</script>

<!--
  type="text", deliberately. type="date" would re-summon the native browser
  calendar on top of this one, which is the whole thing being replaced.
  autocomplete is off because the browser's own suggestions overlay the picker.
-->
<input
  bind:this={input}
  type="text"
  class={klass}
  {id}
  {name}
  {disabled}
  {required}
  {placeholder}
  aria-label={ariaLabel}
  autocomplete="off"
/>
