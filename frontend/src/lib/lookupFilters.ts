// Business rule: narrow the selectable "Hjemmel" and "Afgørelsesbrev" options
// based on the chosen ansøgningstype (and, for "Midlertidig kørsel", the school
// type). Only "Midlertidig kørsel" is restricted today; every other
// ansøgningstype shows all active options unchanged.
//
// Options are matched by their TEXT (label), not by id: ids are per-environment
// autoincrements, whereas the afgørelsesbrev/hjemmel texts are the stable
// business keys in this system (the afgoerelsesbreve RPA keys its letter logic
// off the exact same afgørelsesbrev texts).

export type LookupOption = { id: number | string; label: string };

export type SkoleType = "folkeskole" | "ungdomsuddannelse" | null;

const MIDLERTIDIG = "Midlertidig kørsel";

// Collapse whitespace + trim so trivial spacing differences don't break a match.
function normalize(text: string): string {
  return String(text ?? "").replace(/\s+/g, " ").trim();
}

// Looser form used to match hjemmel labels against the keys below.
//
// The keys are written with the parenthetical descriptor the paragraphs are
// usually quoted with — "§ 26, stk. 1 (afstand)" — but the Hjemmel lookup table
// stores them without brackets: "§ 26, stk. 1 afstand". Matching on the exact
// text meant five of the six mappings never fired, and the dropdown silently
// showed everything. Dropping brackets and case makes both spellings meet.
function canonicalLabel(text: string | null | undefined): string {
  return normalize(String(text ?? "").replace(/[()]/g, ""))
    .toLowerCase();
}

// Allowed afgørelsesbrev texts per selected hjemmel.
const HJEMMEL_AFGOERELSESBREVE: Record<string, string[]> = {
  "§ 26, stk. 1 (afstand)": [
    "Afslag: § 26, stk. 1, nr. 1 (afstand)",
    "Afslag: § 26, stk. 1, nr. 2 (farlig skolevej)",
    "Bevilling: § 26, stk. 1, nr. 1 (afstand)",
    "Bevilling: § 26, stk. 1, nr. 2 (farlig skolevej)",
    "Påtænkt afslag: § 26, stk. 1, nr. 2 (farlig skolevej)",
    "Påtænkt bevilling: § 26, stk. 1 (afstand)",
  ],
  // No midlertidig letters here. AFGOERELSESBREV_ALLOW already pins a
  // Midlertidig kørsel to exactly two letters for its school type, and the
  // status picks one of those two — so the hjemmel adds nothing, and
  // filterAfgoerelsesbreve skips this map entirely for midlertidig.
  //
  // They used to be listed, as a workaround: this map would otherwise strip
  // the very letters the allow-list had just selected, emptying the dropdown.
  // Skipping the map is the same fix without the surprise of folkeskole
  // letters appearing under a paragraph they only half belong to.
  "§ 26, stk. 2 (sygdom)": [
    "Bevilling: § 26, stk. 2 (sygdom)",
    "Påtænkt bevilling: § 26, stk. 2 (sygdom)",
  ],
  "§ 26, stk. 1 og 2": [
    "Påtænkt afslag: § 26, stk. 2 (sygdom)",
    "Påtænkt ophør: § 26, stk. 2 (sygdom)",
  ],
  "§ 33, stk. 3 (ungdomsskolen)": [
    "Afslag: § 33, stk. 3 (ungdomsskolen)",
  ],
  "§ 36, stk. 3 (frit skolevalg)": [
    "Afslag: § 26, stk. 6, § 36, stk. 3 (frit skolevalg)",
    "Bevilling: § 26, stk. 2, § 36, stk. 3 (frit skolevalg)",
  ],
  "§ 36, stk. 4 (retten til at forblive)": [
    "Bevilling: § 26, stk. 2, § 36, stk. 4 (retten til at forblive)",
    "Påtænkt afslag: § 26, stk. 2, § 36, stk. 4 (retten til at forblive)",
  ],
  "§ 9, stk. 4 (UngiAarhus)": [
    "Afslag: § 9, stk. 4 (UngiAarhus)",
  ],
};

// The hjemler Befordring offers per status, on an ordinary Fast kørsel.
//
// Each list is exactly the hjemler that HAVE a letter of that category once the
// midlertidig-only letters are removed. Offering any other one let a caseworker
// pick a legal basis and then find the afgørelsesbrev dropdown empty.
//
// The two lists differ, and the differences are the point:
//
//   § 26, stk. 2 sygdom      grants only. Its afslag letters are the two
//                            midlertidig ones, which a Fast kørsel never sees.
//   § 26, stk. 1 og 2        refusals only — it carries a påtænkt afslag and a
//                            påtænkt ophør, no bevilling.
//   § 33, stk. 3, § 9 stk. 4 refusals only.
//   § 10 (brækket ben)       midlertidig only, excluded before this map.
//
// A missing key means no narrowing. All three categories are specified today.
//
// Spelling follows the Hjemmel lookup table; canonicalLabel reconciles it with
// the bracketed form used in HJEMMEL_AFGOERELSESBREVE.
const HJEMLER_PR_STATUS: Partial<Record<AfgoerelseKategori, string[]>> = {
  bevilling: [
    "§ 26, stk. 1 afstand",
    "§ 26, stk. 2 sygdom",
    "§ 36, stk. 3 frit skolevalg",
    "§ 36, stk. 4 retten til at forblive",
  ],
  afslag: [
    "§ 26, stk. 1 afstand",
    "§ 26, stk. 1 og 2",
    "§ 33, stk. 3 (ungdomsskolen)",
    "§ 36, stk. 3 frit skolevalg",
    "§ 36, stk. 4 retten til at forblive",
    "§ 9, stk. 4 (UngiAarhus)",
  ],
  // Ending a bevilling is only ever done under this one paragraph, and there
  // is exactly one letter for it. A bevilling granted under a different
  // paragraph still shows that one, because filterHjemler keeps the stored
  // value — and the ophør letter reaches it through the exemption in
  // filterAfgoerelsesbreve.
  ophoer: ["§ 26, stk. 2 sygdom"],
};

// Allowed afgørelsesbrev texts per "Midlertidig kørsel" + school type.
const AFGOERELSESBREV_ALLOW: Record<string, string[]> = {
  [`${MIDLERTIDIG}|folkeskole`]: [
    "Midlertidig kørsel bevilling: § 26, stk. 2 (brækket ben folkeskole)",
    "Midlertidig kørsel afslag: § 26, stk. 2 (brækket ben folkeskole)",
  ],
  [`${MIDLERTIDIG}|ungdomsuddannelse`]: [
    "Midlertidig kørsel bevilling: § 10 (brækket ben ungdomssuddannelse)",
    "Midlertidig kørsel afslag: § 10 (brækket ben ungdomssuddannelse)",
  ],
};

// Allowed hjemmel texts per "Midlertidig kørsel" + school type.
//
// Confirmed against the letter bodies in the template workbook: the folkeskole
// letters cite "folkeskolelovens § 26", the ungdomsuddannelse ones cite
// "bekendtgørelse om lov om befordringsrabat til uddannelsessøgende § 10".
// Two different statutes — § 10 cannot apply to a folkeskole pupil, and § 26
// cannot apply to an ungdomsuddannelse student — so neither list may grow to
// include the other's paragraph.
//
// Not keyed by status: the hjemmel follows the statute the student falls
// under, and that does not change between granting and refusing. Only the
// LETTER differs — see AFGOERELSESBREV_ALLOW, which carries a bevilling and an
// afslag variant for each school type.
//
// A midlertidig kørsel is never set to Ophørt, so that status never reaches
// this map; BevillingTable withholds it from the dropdown.
const HJEMMEL_ALLOW: Record<string, string[]> = {
  [`${MIDLERTIDIG}|folkeskole`]: ["§ 26, stk. 2 sygdom"],
  [`${MIDLERTIDIG}|ungdomsuddannelse`]: ["§ 10 (brækket ben)"],
};

// Returns the allow-list key when the current selection is a restricted case,
// otherwise null (meaning: no restriction, show everything).
function ruleKey(ansoegningstype: string | null | undefined, skoleType: SkoleType): string | null {
  if (ansoegningstype === MIDLERTIDIG && skoleType) {
    return `${MIDLERTIDIG}|${skoleType}`;
  }
  return null;
}

// Values that ONLY apply to Midlertidig kørsel — hidden for every other type.
// The afgørelsesbrev set is exactly the union of the allow-lists above (all four
// "Midlertidig kørsel …" texts). For hjemmel we only exclude § 10, since
// § 26, stk. 2 (sygdom) is also used by non-midlertidig afgørelsesbreve.
const MIDLERTIDIG_ONLY_AFGOERELSESBREVE = Object.values(AFGOERELSESBREV_ALLOW).flat();
const MIDLERTIDIG_ONLY_HJEMLER = ["§ 10 (brækket ben)"];

function applyRule(
  all: LookupOption[] | undefined,
  allow: string[] | undefined,
  excludeWhenUnrestricted: string[]
): LookupOption[] {
  const options = all ?? [];

  // Restricted case (Midlertidig kørsel + skoletype): show only the allow-list.
  if (allow) {
    const allowed = new Set(allow.map(normalize));
    return options.filter((option) => allowed.has(normalize(option.label)));
  }

  // Unrestricted case (all other types): show everything EXCEPT Midlertidig-only values.
  const excluded = new Set(excludeWhenUnrestricted.map(normalize));
  return options.filter((option) => !excluded.has(normalize(option.label)));
}

/**
 * True when a bevilling is of type "Midlertidig kørsel".
 *
 * Midlertidig kørsel is a short-term grant made on a different basis, so the
 * afstandskriterie fields, befordringsudvalg and PPR ansvarlig do not apply to
 * it and are hidden. Compared through the same normalize() as the lookup
 * filtering, so trivial spacing differences do not break the match.
 */
export function isMidlertidigKoersel(
  ansoegningstype: string | null | undefined
): boolean {
  return normalize(String(ansoegningstype ?? "")) === normalize(MIDLERTIDIG);
}


/**
 * The hjemler selectable for a bevilling.
 *
 * `statusLabel` is the status CHOSEN in the form — "Auto" (or null) for the
 * calculated statuses, which classify as "bevilling". The list it narrows to
 * comes from HJEMLER_PR_STATUS; a status with no list there is not narrowed.
 *
 * `currentLabel` is always kept in the list even when it does not belong. A
 * <select> whose bound value is absent from its options renders blank, which
 * reads as the saved hjemmel having been erased — filtering must never hide
 * data that is already stored.
 */
export function filterHjemler(
  all: LookupOption[] | undefined,
  ansoegningstype: string | null | undefined,
  skoleType: SkoleType,
  statusLabel?: string | null,
  currentLabel?: string | null
): LookupOption[] {
  const key = ruleKey(ansoegningstype, skoleType);
  const filtered = applyRule(all, key ? HJEMMEL_ALLOW[key] : undefined, MIDLERTIDIG_ONLY_HJEMLER);

  // Midlertidig kørsel is already down to one hjemmel per skoletype via
  // HJEMMEL_ALLOW, and its letters sit outside these lists, so narrowing it
  // again would empty the dropdown.
  if (isMidlertidigKoersel(ansoegningstype)) return filtered;

  const tilladte = HJEMLER_PR_STATUS[statusKategori(statusLabel)];

  // No list for this status means no narrowing — see the map.
  if (!tilladte) return filtered;

  const tilladt = new Set(tilladte.map(canonicalLabel));
  const current = currentLabel ? canonicalLabel(currentLabel) : null;

  return filtered.filter(
    (option) =>
      tilladt.has(canonicalLabel(option.label)) ||
      (current !== null && canonicalLabel(option.label) === current)
  );
}

/**
 * Which bevilling-status an afgørelsesbrev belongs with.
 *
 * "bevilling" covers every status that is not a manual Afslag/Ophørt — i.e. the
 * automatically calculated ones (Ny, Påbegyndt, Aktiv, Kommende, Udløbet,
 * Fejlet) and "no status chosen yet".
 */
export type AfgoerelseKategori = "afslag" | "ophoer" | "bevilling";

// Keyword matching, not "starts with". Five rejection letters do not begin with
// "Afslag:" — the three "Påtænkt afslag: …" and the two "Midlertidig kørsel
// afslag: …" — so a prefix rule would hide real options. The Danish letters are
// folded so "ophør" and "ophoert" match each other.
function normalizeKeyword(label: string | null | undefined): string {
  return String(label ?? "")
    .toLowerCase()
    .replace(/ø/g, "oe")
    .replace(/å/g, "aa")
    .replace(/æ/g, "ae")
    .replace(/\s+/g, " ")
    .trim();
}

/**
 * The status an afgørelsesbrev belongs with.
 *
 * "Påtænkt" letters follow their own keyword: a påtænkt ophør belongs with
 * Ophørt and a påtænkt afslag with Afslag, so each is offered only where it is
 * relevant.
 *
 * Deriving this from the text (rather than listing all 18 rows) means a new
 * afgørelsesbrev added to the lookup table is classified automatically.
 */
export function afgoerelsesbrevKategori(
  label: string | null | undefined
): AfgoerelseKategori {
  const text = normalizeKeyword(label);

  // Checked before "afslag" so precedence is explicit, even though no current
  // text contains both.
  if (text.includes("ophoer")) return "ophoer";
  if (text.includes("afslag")) return "afslag";

  return "bevilling";
}

/** The category a bevilling's status belongs to. */
export function statusKategori(
  statusLabel: string | null | undefined
): AfgoerelseKategori {
  const text = normalizeKeyword(statusLabel);

  if (text === "ophoert") return "ophoer";
  if (text === "afslag") return "afslag";

  return "bevilling";
}

/**
 * Narrow afgørelsesbreve to those that belong with the chosen status.
 *
 * One rule for every status: the letter's category must equal the status's.
 * The "show everything except afslag/ophør on a calculated status" case is not
 * a separate branch — those statuses simply classify as "bevilling".
 *
 * `currentLabel` is always kept in the list even when it does not match. A
 * <select> whose bound value is absent from its options silently renders blank,
 * which would look like the saved afgørelsesbrev had been erased — filtering
 * must never hide data that is already stored.
 */
/**
 * True when `label` is among the options — used by the edit forms to decide
 * whether a chosen afgørelsesbrev survives a change of status or hjemmel.
 */
export function containsLabel(
  options: LookupOption[],
  label: string | null | undefined
): boolean {
  if (!label) return false;
  const target = canonicalLabel(label);
  return options.some((option) => canonicalLabel(option.label) === target);
}

export function filterAfgoerelsesbreveByStatus(
  all: LookupOption[] | undefined,
  statusLabel: string | null | undefined,
  currentLabel?: string | null
): LookupOption[] {
  const kategori = statusKategori(statusLabel);
  const current = currentLabel ? normalize(currentLabel) : null;

  return (all ?? []).filter(
    (option) =>
      afgoerelsesbrevKategori(option.label) === kategori ||
      (current !== null && normalize(option.label) === current)
  );
}


export function filterAfgoerelsesbreve(
  all: LookupOption[] | undefined,
  ansoegningstype: string | null | undefined,
  skoleType: SkoleType,
  selectedHjemmelLabel?: string | null
): LookupOption[] {
  const key = ruleKey(ansoegningstype, skoleType);
  let filtered = applyRule(all, key ? AFGOERELSESBREV_ALLOW[key] : undefined, MIDLERTIDIG_ONLY_AFGOERELSESBREVE);

  // Midlertidig kørsel is already down to two letters for its school type, and
  // the status picks one of them. Running the hjemmel map on top could only
  // remove one of the two correct answers — which is exactly what it did
  // before the midlertidig letters were listed in it as a workaround.
  if (selectedHjemmelLabel && !isMidlertidigKoersel(ansoegningstype)) {
    const canonicalHjemmel = canonicalLabel(selectedHjemmelLabel);
    const mappingKey = Object.keys(HJEMMEL_AFGOERELSESBREVE).find(
      (key) => canonicalLabel(key) === canonicalHjemmel
    );

    // A hjemmel with no mapping (e.g. "§ 10 (brækket ben)", which the
    // midlertidig allow-list already covers) restricts nothing.
    if (mappingKey) {
      const allowed = new Set(HJEMMEL_AFGOERELSESBREVE[mappingKey].map(canonicalLabel));

      // Ophør letters are exempt. The mapping pairs a legal basis with the
      // letters that DECIDE an application under it; ending a bevilling is not
      // a new legal basis. A bevilling granted under "§ 26, stk. 1 afstand"
      // keeps that hjemmel when it ends — the caseworker cannot rewrite what it
      // was granted on — so without this the ophør letter is unreachable for
      // six of the seven hjemler.
      filtered = filtered.filter(
        (opt) =>
          allowed.has(canonicalLabel(opt.label)) ||
          afgoerelsesbrevKategori(opt.label) === "ophoer"
      );
    }
  }

  return filtered;
}
