import { useServer } from "../context/ServerContext";
import { useT } from "../i18n/LanguageContext";

/** The dropdown at the top of the sidebar: which Discord server the pages are about. */
export function ServerPicker() {
  const t = useT();
  const { server, servers, selectServer } = useServer();

  if (servers.length === 0) return <p className="muted">{t("server.none")}</p>;

  return (
    <div>
      <label htmlFor="server-picker">{t("server.label")}</label>
      <select id="server-picker" value={server?.id ?? ""} onChange={(event) => selectServer(event.target.value)}>
        {servers.map((option) => (
          <option key={option.id} value={option.id}>
            {option.name}
          </option>
        ))}
      </select>
    </div>
  );
}
