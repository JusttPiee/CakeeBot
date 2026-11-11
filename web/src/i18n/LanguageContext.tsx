import { createContext, useCallback, useContext, useMemo, useState, type ReactNode } from "react";
import { en, type TextKey } from "./en";
import { vi } from "./vi";

export type Language = "en" | "vi";

const LANGUAGE_KEY = "cake.lang";
const DICTIONARIES: Record<Language, Record<TextKey, string>> = { en, vi };

interface LanguageContextValue {
  language: Language;
  setLanguage: (language: Language) => void;
}

// A "context" is a value every component below the provider can read, without it being
// passed down by hand through every component in between. Here: the chosen language.
const LanguageContext = createContext<LanguageContextValue | null>(null);

function savedLanguage(): Language {
  try {
    return localStorage.getItem(LANGUAGE_KEY) === "vi" ? "vi" : "en"; // English unless Vietnamese was chosen
  } catch {
    return "en";
  }
}

/** Wrap the app in this once (see App.tsx). It holds the language and remembers the choice. */
export function LanguageProvider({ children }: { children: ReactNode }) {
  const [language, setLanguageState] = useState<Language>(savedLanguage);

  const setLanguage = useCallback((next: Language) => {
    setLanguageState(next);
    try {
      localStorage.setItem(LANGUAGE_KEY, next);
    } catch {
      // Storage is blocked: the choice just lasts until the page is closed.
    }
  }, []);

  const value = useMemo(() => ({ language, setLanguage }), [language, setLanguage]);
  return <LanguageContext.Provider value={value}>{children}</LanguageContext.Provider>;
}

export function useLanguage(): LanguageContextValue {
  const value = useContext(LanguageContext);
  if (value === null) throw new Error("useLanguage must be used inside <LanguageProvider>");
  return value;
}

export type Translate = (key: TextKey, variables?: Record<string, string | number>) => string;

/**
 * Gives a component the translate function:
 *
 *   const t = useT();
 *   t("common.save")                          // "Save" or "Lưu"
 *   t("memory.people.count", { count: 17 })   // "17 people"
 */
export function useT(): Translate {
  const { language } = useLanguage();
  return useCallback(
    (key, variables) => fillVariables(DICTIONARIES[language][key], variables),
    [language],
  );
}

// "{count} people" + { count: 17 } => "17 people"
function fillVariables(text: string, variables?: Record<string, string | number>): string {
  if (!variables) return text;
  return text.replace(/\{(\w+)\}/g, (placeholder, name: string) =>
    name in variables ? String(variables[name]) : placeholder,
  );
}
