import { NavLink } from "react-router-dom";
import { useStatus } from "../context/StatusContext";
import { useT } from "../i18n/LanguageContext";
import type { TextKey } from "../i18n/en";
import { LanguageSwitch } from "./LanguageSwitch";
import { RestartButton } from "./RestartButton";
import { ServerPicker } from "./ServerPicker";
import styles from "./Sidebar.module.css";

const PAGES: { path: string; icon: string; label: TextKey }[] = [
  { path: "/memory", icon: "🧠", label: "nav.memory" },
  { path: "/channels", icon: "💬", label: "nav.channels" },
  { path: "/config", icon: "⚙️", label: "nav.config" },
  { path: "/logs", icon: "📜", label: "nav.logs" },
];

/** The left column: server picker on top, the pages in the middle, restart and language at the bottom. */
export function Sidebar() {
  const t = useT();
  const { status } = useStatus();

  return (
    <nav className={styles.sidebar}>
      <div className={styles.brand}>🍰 {status?.bot_name ?? "Cake"}</div>
      <ServerPicker />

      <ul className={styles.pages}>
        {PAGES.map((page) => (
          <li key={page.path}>
            {/* NavLink knows whether its page is the open one, and tells us through isActive */}
            <NavLink to={page.path} className={({ isActive }) => `${styles.page} ${isActive ? styles.active : ""}`}>
              <span aria-hidden="true">{page.icon}</span>
              {t(page.label)}
              {page.path === "/config" && status?.restart_needed && (
                <span className={styles.dot} title={t("nav.restartNeeded")} />
              )}
            </NavLink>
          </li>
        ))}
      </ul>

      <div className={styles.bottom}>
        <RestartButton />
        <LanguageSwitch />
      </div>
    </nav>
  );
}
