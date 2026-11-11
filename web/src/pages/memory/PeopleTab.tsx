import { useState } from "react";
import { listUsers } from "../../api/memory";
import type { UserSummary } from "../../api/types";
import { ListDetail } from "../../components/ListDetail";
import { LoadProblem } from "../../components/LoadProblem";
import { SearchBox } from "../../components/SearchBox";
import { UnsavedBar } from "../../components/UnsavedBar";
import { useApi } from "../../hooks/useApi";
import { useGuardedSelection } from "../../hooks/useGuardedSelection";
import { useT } from "../../i18n/LanguageContext";
import styles from "./MemoryPage.module.css";
import { UserNoteDetail } from "./UserNoteDetail";

/** Does this person match what was typed in the search box? Name or id, upper or lower case. */
function matchesSearch(person: UserSummary, search: string): boolean {
  const wanted = search.trim().toLowerCase();
  return person.name.toLowerCase().includes(wanted) || person.id.includes(wanted);
}

/** The People tab: everyone Cake has a note about on the left, the picked person's note on the right. */
export function PeopleTab({ serverId }: { serverId: string }) {
  const t = useT();
  const people = useApi(() => listUsers(serverId), [serverId]);
  const [search, setSearch] = useState("");
  const selection = useGuardedSelection();

  if (people.error && !people.data) return <LoadProblem error={people.error} onRetry={people.reload} />;
  if (!people.data) return <p className="muted">{t("common.loading")}</p>;

  const everyone = people.data;
  const shown = everyone.filter((person) => matchesSearch(person, search));

  const afterDelete = () => {
    selection.jumpTo(null);
    people.reload();
  };

  const renderPerson = (person: UserSummary) => (
    <>
      <div className={styles.rowTitle}>
        {person.name || <span className="muted">{t("memory.people.unnamed")}</span>}
        {person.personality_off && <span className="badge">{t("memory.people.optedOut")}</span>}
        {person.fact_count > 0 && <span className="badge">{t("memory.people.facts", { count: person.fact_count })}</span>}
      </div>
      <div className={styles.rowText}>{person.description || person.id}</div>
    </>
  );

  return (
    <ListDetail
      items={shown}
      getKey={(person) => person.id}
      renderItem={renderPerson}
      selectedKey={selection.selected}
      onSelect={selection.select}
      emptyText={t(everyone.length === 0 ? "memory.people.empty" : "memory.people.noMatch")}
      toolbar={
        <>
          <span className={styles.count}>{t("memory.people.count", { count: everyone.length })}</span>
          <SearchBox value={search} onChange={setSearch} placeholder={t("memory.people.search")} />
        </>
      }
      detail={
        selection.selected === null ? null : (
          <>
            {selection.askingToDiscard && (
              <UnsavedBar onDiscard={selection.discard} onKeepEditing={selection.keepEditing} />
            )}
            {/* key: a different person gets a brand-new component, with fresh form state */}
            <UserNoteDetail
              key={selection.selected}
              serverId={serverId}
              userId={selection.selected}
              onListChanged={people.reload}
              onDeleted={afterDelete}
              onDirtyChange={selection.setDirty}
            />
          </>
        )
      }
    />
  );
}
