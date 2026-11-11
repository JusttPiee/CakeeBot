import { listEvents } from "../../api/memory";
import type { EventNote } from "../../api/types";
import { ListDetail } from "../../components/ListDetail";
import { LoadProblem } from "../../components/LoadProblem";
import { UnsavedBar } from "../../components/UnsavedBar";
import { useApi } from "../../hooks/useApi";
import { useGuardedSelection } from "../../hooks/useGuardedSelection";
import { useT } from "../../i18n/LanguageContext";
import { EventForm } from "./EventForm";
import styles from "./MemoryPage.module.css";

/** The Events tab: planned events, the coming ones first, the past ones faded below them. */
export function EventsTab({ serverId }: { serverId: string }) {
  const t = useT();
  const events = useApi(() => listEvents(serverId), [serverId]);
  const selection = useGuardedSelection();

  if (events.error && !events.data) return <LoadProblem error={events.error} onRetry={events.reload} />;
  if (!events.data) return <p className="muted">{t("common.loading")}</p>;

  // The bot sends them soonest first. Keep that order inside each group.
  const ordered = [...events.data.filter((event) => !event.past), ...events.data.filter((event) => event.past)];
  const selected = ordered.find((event) => event.slug === selection.selected) ?? null;

  const afterSave = (slug: string) => {
    selection.jumpTo(slug); // a renamed event has a new slug: follow it
    events.reload();
  };

  const afterDelete = () => {
    selection.jumpTo(null);
    events.reload();
  };

  const renderEvent = (event: EventNote) => (
    <div className={event.past ? styles.faded : ""}>
      <div className={styles.rowTitle}>
        {event.title}
        {event.past && <span className="badge">{t("memory.events.past")}</span>}
      </div>
      <div className={styles.rowText}>{event.when}</div>
    </div>
  );

  return (
    <ListDetail
      items={ordered}
      getKey={(event) => event.slug}
      renderItem={renderEvent}
      selectedKey={selection.selected}
      onSelect={selection.select}
      emptyText={t("memory.events.empty")}
      detail={
        selected === null ? null : (
          <>
            {selection.askingToDiscard && (
              <UnsavedBar onDiscard={selection.discard} onKeepEditing={selection.keepEditing} />
            )}
            {/* The key includes the saved values, so the form starts fresh after a save */}
            <EventForm
              key={`${selected.slug}|${selected.when}|${selected.details}`}
              serverId={serverId}
              event={selected}
              onSaved={afterSave}
              onDeleted={afterDelete}
              onDirtyChange={selection.setDirty}
            />
          </>
        )
      }
    />
  );
}
