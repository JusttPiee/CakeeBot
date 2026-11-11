import { LanguageSwitch } from "../components/LanguageSwitch";
import { useT } from "../i18n/LanguageContext";
import styles from "./TokenNeededPage.module.css";

/** Shown instead of the whole app when the bot refuses this browser: it has no (or an old) secret token. */
export function TokenNeededPage() {
  const t = useT();
  return (
    <div className={styles.page}>
      <div className={styles.card}>
        <h1>🔑 {t("token.title")}</h1>
        <p>{t("token.why")}</p>
        <p>{t("token.how")}</p>
        <pre className={styles.example}>{t("token.example")}</pre>
        <div className={styles.language}>
          <LanguageSwitch />
        </div>
      </div>
    </div>
  );
}
