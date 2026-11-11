import { listRecent } from "../../api/memory";
import type { RecentEntry } from "../../api/types";
import { EmptyState } from "../../components/EmptyState";
import { LoadProblem } from "../../components/LoadProblem";
import { useApi } from "../../hooks/useApi";
import { useT } from "../../i18n/LanguageContext";
import styles from "./RecentTab.module.css";

/**
 * The "Recent" tab: the shared short-term memory Cake keeps in RAM (recent_activity.rb on the bot).
 * Read-only, for checking what Cake knows about other channels. It is empty after every restart.
 * Lines from private channels are marked: Cake only uses those in their own channel.
 */
export function RecentTab({ serverId }: { serverId: string }) {
  const t = useT();
  const recent = useApi(() => listRecent(serverId), [serverId]);

  if (recent.error && !recent.data) return <LoadProblem error={recent.error} onRetry={recent.reload} />;
  if (!recent.data) return <p className="muted">{t("common.loading")}</p>;

  return (
    <div className={styles.tab}>
      <div className="actions">
        <p className="help">{t("memory.recent.intro")}</p>
        <button type="button" onClick={recent.reload}>
          ↻ {t("memory.recent.reload")}
        </button>
      </div>
      {recent.data.length === 0 ? (
        <EmptyState text={t("memory.recent.empty")} />
      ) : (
        <ul className={styles.list}>
          {recent.data.map((entry, index) => (
            // The bot sends them newest first; there is no id, and the list is only redrawn whole.
            <RecentLine key={`${entry.time}-${index}`} entry={entry} />
          ))}
        </ul>
      )}
    </div>
  );
}

function RecentLine({ entry }: { entry: RecentEntry }) {
  const t = useT();
  const time = new Date(entry.time).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });

  return (
    <li className={styles.line}>
      <div className={styles.head}>
        <span className="muted">{time}</span>
        <span className={styles.channel}># {entry.channel_name}</span>
        {!entry.public && <span className="badge">{t("memory.recent.private")}</span>}
        <span className={styles.speaker}>{entry.speaker_name}</span>
      </div>
      <p className={styles.text}>{entry.text}</p>
      {entry.kind === "exchange" ? (
        <p className={styles.answer}>
          <span className="muted">Cake: </span>
          {entry.answer}
        </p>
      ) : (
        <p className={`${styles.answer} muted`}>{t("memory.recent.notAnswered")}</p>
      )}
    </li>
  );
}
