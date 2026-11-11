import { useStatus, type Connection } from "../context/StatusContext";
import { useT } from "../i18n/LanguageContext";
import type { TextKey } from "../i18n/en";
import styles from "./ConnectionBanner.module.css";

const MESSAGES: Record<Exclude<Connection, "ok">, TextKey> = {
  reconnecting: "connection.reconnecting",
  restarting: "connection.restarting",
  stopped: "connection.stopped",
};

/** A bar across the top while the bot can't be reached. Nothing is shown when all is well. */
export function ConnectionBanner() {
  const t = useT();
  const { connection } = useStatus();
  if (connection === "ok") return null;

  return (
    <div className={`${styles.banner} ${connection === "stopped" ? styles.stopped : ""}`} role="status">
      {connection !== "stopped" && <span className={styles.spinner} aria-hidden="true" />}
      {t(MESSAGES[connection])}
    </div>
  );
}
