// Ambient declarations for flowbite-datepicker, which ships none of its own.
//
// In its OWN file, not app.d.ts, and deliberately: app.d.ts has a top-level
// `import`, which makes it a module, and inside a module `declare module "x"`
// means *augment* x rather than *declare* x. Augmenting a package that has no
// types of its own fails — which is why the simple-datatables block next door
// works (that package does ship types) and this one did not.
//
// This file must therefore stay free of top-level imports and exports.

/**
 * flowbite-datepicker ships no type declarations. Declared here, next to the
 * simple-datatables one above, rather than silenced with `any` at the import
 * in DateInput.svelte.
 *
 * Only the surface DateInput actually uses. The option names are worth having
 * checked: the library ignores an option it does not recognise, silently, so
 * `weekNumbers` instead of `calendarWeeks` would simply produce a calendar
 * with no week numbers and no error anywhere.
 */
declare module "flowbite-datepicker/Datepicker" {
  export interface DatepickerOptions {
    language?: string;
    format?: string;
    calendarWeeks?: boolean;
    weekStart?: number;
    autohide?: boolean;
    todayBtn?: boolean;
    todayBtnMode?: 0 | 1;
    todayHighlight?: boolean;
    clearBtn?: boolean;
    minDate?: string | Date | null;
    maxDate?: string | Date | null;
    orientation?: string;
    container?: string;
    buttonClass?: string;
    title?: string;
    showOnClick?: boolean;
    showOnFocus?: boolean;
    startView?: 0 | 1 | 2 | 3;
    maxView?: 0 | 1 | 2 | 3;
  }

  export interface SetDateOptions {
    clear?: boolean;
    render?: boolean;
    autohide?: boolean;
  }

  export default class Datepicker {
    constructor(element: HTMLElement, options?: DatepickerOptions);

    /** Installed locales, keyed by language code. Assign to register one. */
    static readonly locales: Record<string, Record<string, unknown>>;

    /** The popup. `picker.element` is the positioned container. */
    readonly picker?: { element: HTMLElement };

    getDate(): Date | undefined;
    getDate(format: string): string | undefined;
    setDate(date: string | Date, options?: SetDateOptions): void;
    setDate(options: SetDateOptions): void;
    setOptions(options: DatepickerOptions): void;
    show(): void;
    hide(): void;
    destroy(): void;
  }
}
