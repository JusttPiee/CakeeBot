import { useT } from "../i18n/LanguageContext";
import styles from "./UnsavedBar.module.css";

interface UnsavedBarProps {
  onDiscard: () => void;
  onKeepEditing: () => void;
}

/** Asks, inside the page, what to do with unsaved changes when the user picks another item. */
export function UnsavedBar({ onDiscard, onKeepEditing }: UnsavedBarProps) {
  const t = useT();
  return (
    <div className={styles.bar} role="alert">
      <span>{t("common.unsaved")}</span>
      <button type="button" className="danger" onClick={onDiscard}>
        {t("common.discard")}
      </button>
      <button type="button" onClick={onKeepEditing}>
        {t("common.keepEditing")}
      </button>
    </div>
  );
}
