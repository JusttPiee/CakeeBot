import { SearchBox } from "../../components/SearchBox";
import { useT } from "../../i18n/LanguageContext";
import type { LogFilter } from "./filterLogLines";
import styles from "./LogsPage.module.css";

interface LogFiltersProps {
  filter: LogFilter;
  onFilterChange: (filter: LogFilter) => void;
  serverNames: string[];
  days: string[];
  day: string;
  onDayChange: (day: string) => void;
}

/** The row of controls above the log: kind, server, search text and day. */
export function LogFilters({ filter, onFilterChange, serverNames, days, day, onDayChange }: LogFiltersProps) {
  const t = useT();

  return (
    <div className={styles.filters}>
      <div>
        <label htmlFor="log-kind">{t("logs.kindLabel")}</label>
        <select
          id="log-kind"
          value={filter.kind}
          onChange={(event) => onFilterChange({ ...filter, kind: event.target.value as LogFilter["kind"] })}
        >
          <option value="all">{t("logs.kind.all")}</option>
          <option value="chat">{t("logs.kind.chat")}</option>
          <option value="system">{t("logs.kind.system")}</option>
        </select>
      </div>

      <div>
        <label htmlFor="log-server">{t("server.label")}</label>
        <select
          id="log-server"
          value={filter.serverName ?? ""}
          onChange={(event) => onFilterChange({ ...filter, serverName: event.target.value || null })}
        >
          <option value="">{t("logs.allServers")}</option>
          {serverNames.map((name) => (
            <option key={name} value={name}>
              {name}
            </option>
          ))}
        </select>
      </div>

      <div>
        <label htmlFor="log-day">{t("logs.dayLabel")}</label>
        <select id="log-day" value={day} onChange={(event) => onDayChange(event.target.value)}>
          {days.map((option) => (
            <option key={option} value={option}>
              {option}
            </option>
          ))}
        </select>
      </div>

      <div className={styles.search}>
        <label>&nbsp;</label>
        <SearchBox
          value={filter.text}
          onChange={(text) => onFilterChange({ ...filter, text })}
          placeholder={t("logs.search")}
        />
      </div>
    </div>
  );
}
