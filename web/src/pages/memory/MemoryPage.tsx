import { Navigate, NavLink, useParams } from "react-router-dom";
import { EmptyState } from "../../components/EmptyState";
import { useServer } from "../../context/ServerContext";
import { useT } from "../../i18n/LanguageContext";
import type { TextKey } from "../../i18n/en";
import { EventsTab } from "./EventsTab";
import { GeneralTab } from "./GeneralTab";
import styles from "./MemoryPage.module.css";
import { PeopleTab } from "./PeopleTab";
import { RecentTab } from "./RecentTab";
import { SummariesTab } from "./SummariesTab";

const TABS: { id: string; label: TextKey }[] = [
  { id: "people", label: "memory.tab.people" },
  { id: "general", label: "memory.tab.general" },
  { id: "events", label: "memory.tab.events" },
  { id: "summaries", label: "memory.tab.summaries" },
  { id: "recent", label: "memory.tab.recent" },
];

/**
 * The Memory page: four tabs over what Cake remembers in the picked server.
 * The open tab is part of the address (/memory/events), so a reload or a bookmark comes back to it.
 */
export function MemoryPage() {
  const t = useT();
  const { tab } = useParams();
  const { server } = useServer();

  if (!TABS.some((known) => known.id === tab)) return <Navigate to="/memory/people" replace />;
  if (server === null) return <EmptyState text={t("server.none")} />;

  return (
    <>
      <h1>
        {t("memory.title")} · {server.name}
      </h1>
      <div className={styles.tabs}>
        {TABS.map(({ id, label }) => (
          <NavLink
            key={id}
            to={`/memory/${id}`}
            className={({ isActive }) => `${styles.tab} ${isActive ? styles.active : ""}`}
          >
            {t(label)}
          </NavLink>
        ))}
      </div>
      {/* key={server.id}: picking another server starts the tab from scratch (nothing stays selected) */}
      {tab === "people" && <PeopleTab key={server.id} serverId={server.id} />}
      {tab === "general" && <GeneralTab key={server.id} serverId={server.id} />}
      {tab === "events" && <EventsTab key={server.id} serverId={server.id} />}
      {tab === "summaries" && <SummariesTab key={server.id} serverId={server.id} />}
      {tab === "recent" && <RecentTab key={server.id} serverId={server.id} />}
    </>
  );
}
