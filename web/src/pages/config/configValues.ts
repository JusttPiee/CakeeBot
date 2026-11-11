// Small pure functions for the Config page: no React here, so they are easy to read and to test.
import type { ConfigField, ConfigValue } from "../../api/types";

/** The value a setting will have after the next restart: the saved one, or else its default. */
export function savedValue(field: ConfigField): ConfigValue {
  return field.saved ?? field.default;
}

/**
 * What was typed, as a real value: a number for number settings, the option for choices.
 * null when it is not allowed (not a whole number, or outside the setting's limits).
 */
export function parseValue(field: ConfigField, typed: string): ConfigValue | null {
  if (field.type === "choice") return field.options?.includes(typed) ? typed : null;

  if (!/^\d+$/.test(typed.trim())) return null; // digits only: no "60.5", no "-3", no "abc"
  const number = Number(typed.trim());
  const min = field.min ?? Number.MIN_SAFE_INTEGER;
  const max = field.max ?? Number.MAX_SAFE_INTEGER;
  return number >= min && number <= max ? number : null;
}
