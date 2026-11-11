import { useStatus } from "../../context/StatusContext";
import { useT } from "../../i18n/LanguageContext";
import styles from "./ConfigPage.module.css";

/** The yellow bar on the Config page while saved settings are waiting for a restart. */
export function RestartBanner() {
  const t = useT();
  const { connection, restart } = useStatus();

  return (
    <div className={styles.restartBanner} role="status">
      <span>⚠️ {t("config.restartBanner")}</span>
      <button type="button" disabled={connection !== "ok"} onClick={() => void restart()}>
        ↻ {t("config.restartNow")}
      </button>
    </div>
  );
}
