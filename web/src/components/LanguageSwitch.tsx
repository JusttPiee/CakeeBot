import { useLanguage, useT, type Language } from "../i18n/LanguageContext";
import styles from "./LanguageSwitch.module.css";

const LANGUAGES: { code: Language; name: string }[] = [
  { code: "en", name: "EN" },
  { code: "vi", name: "VI" },
];

/** Two small buttons, EN | VI. The chosen one is highlighted. */
export function LanguageSwitch() {
  const t = useT();
  const { language, setLanguage } = useLanguage();

  return (
    <div className={styles.switch} role="group" aria-label={t("language.label")}>
      {LANGUAGES.map(({ code, name }) => (
        <button
          key={code}
          type="button"
          className={code === language ? styles.chosen : ""}
          aria-pressed={code === language}
          onClick={() => setLanguage(code)}
        >
          {name}
        </button>
      ))}
    </div>
  );
}
