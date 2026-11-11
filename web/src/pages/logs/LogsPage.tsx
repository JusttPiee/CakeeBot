import { useState } from "react";
import { listLogDays } from "../../api/logs";
import { EmptyState } from "../../components/EmptyState";
import { LoadProblem } from "../../components/LoadProblem";
import { RestartButton } from "../../components/RestartButton";
import { useServer } from "../../context/ServerContext";
import { useApi } from "../../hooks/useApi";
import { useT } from "../../i18n/LanguageContext";
import { BuildMemoryButton } from "./BuildMemoryButton";
import { filterLogLines, type LogFilter } from "./filterLogLines";
import { LogFilters } from "./LogFilters";
import { LogLines } from "./LogLines";
import styles from "./LogsPage.module.css";
import { useLogLines } from "./useLogLines";

const NO_FILTER: LogFilter = { kind: "all", serverName: null, text: "" };

/**
 * The Logs page: the command buttons on top, then the bot's log.
 * The newest day is followed live (new lines appear by themselves); an older day is loaded once.
 */
export function LogsPage() {
  const t = useT();
  const { server, servers } = useServer();
  const days = useApi(listLogDays, []);
  const [pickedDay, setPickedDay] = useState<string | null>(null);
  const [filter, setFilter] = useState<LogFilter>(NO_FILTER);

  const newestDay = days.data?.[0] ?? null;
  const day = pickedDay ?? newestDay; // until a day is picked, show the newest
  const live = day !== null && day === newestDay;
  const log = useLogLines(day, live);

  if (days.error && !days.data) return <LoadProblem error={days.error} onRetry={days.reload} />;
  if (!days.data) return <p className="muted">{t("common.loading")}</p>;

  const shown = filterLogLines(log.lines, filter);

  return (
    <>
      <h1>{t("logs.title")}</h1>

      <div className={styles.commands}>
        <RestartButton />
        {server && <BuildMemoryButton key={server.id} serverId={server.id} serverName={server.name} />}
      </div>

      {day === null ? (
        <EmptyState text={t("logs.none")} />
      ) : (
        <>
          <LogFilters
            filter={filter}
            onFilterChange={setFilter}
            serverNames={servers.map((option) => option.name)}
            days={days.data}
            day={day}
            onDayChange={setPickedDay}
          />

          <div className={styles.statusLine}>
            {live && <span className={styles.live}>{t("logs.live")}</span>}
            <span>{t("logs.shown", { shown: shown.length, total: log.lines.length })}</span>
            {log.problem && <span className="error-text">{t("common.loadFailed", { message: log.problem })}</span>}
          </div>

          {shown.length === 0 ? (
            <EmptyState text={t(log.lines.length === 0 ? "logs.empty" : "logs.noMatch")} />
          ) : (
            <LogLines lines={shown} />
          )}
        </>
      )}
    </>
  );
}
