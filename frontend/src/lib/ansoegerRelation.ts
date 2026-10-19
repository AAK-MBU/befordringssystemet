// The "Ansøger relation" (relation_til_barnet) vocabulary.
//
// Kept here rather than inline in the two components that offer it, because
// they had already drifted apart from each other and from the OS2Forms mapping
// — which is what caused a form-created bevilling to show an empty relation the
// moment it was opened for editing.
//
// relation_til_barnet is a free-text column, not a lookup table, and the
// backend stores whatever os2forms_mapping.get_relation_til_barnet returns.
// That includes values this list cannot enumerate: for an applicant without
// custody the form returns `angiv_din_tilknytning_til_barnet` verbatim, i.e.
// whatever the applicant typed. A <select> over a free-text column can
// therefore never be complete, which is why callers should build their options
// with ansoegerRelationOptions() rather than using the list directly.

// Spelled to match backend/app/utils/os2forms_mapping.py, which returns
// "Forældremyndighed" — most bevillinger arrive through that flow, and it is
// the correct Danish noun. Rows created before this was aligned hold
// "Forældremyndig" and are carried by the fallback in ansoegerRelationOptions.
export const ANSOEGER_RELATIONER = [
  "Forældremyndighed",
  "Værge",
  "Plejeforælder",
  "Ansøger selv",
  "Uddannelsesinstitution",
  // Tilføjet efter ønske fra Befordring. Placeret ved siden af
  // Uddannelsesinstitution, fordi det er samme slags ansøger: en institution,
  // ikke en person omkring barnet.
  "Skole",
  "Sagsbehandler",
  "Bosted"
] as const;


/**
 * The options to offer for a given stored value.
 *
 * A <select> silently renders blank when its value matches no option, which
 * makes a stored relation look unset — and, where the binding is two-way,
 * clears it. Appending the current value when it is not one of the known ones
 * keeps every existing relation visible and selectable, whatever wrote it.
 */
export function ansoegerRelationOptions(current: string | null | undefined): string[] {
  const value = (current ?? "").trim();
  const known: string[] = [...ANSOEGER_RELATIONER];

  if (!value || known.includes(value)) {
    return known;
  }

  return [...known, value];
}
