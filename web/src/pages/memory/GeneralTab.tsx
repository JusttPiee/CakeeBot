import { useEffect, useState } from "react";
import { listGeneral } from "../../api/memory";
import type { GeneralNote } from "../../api/types";
import { ListDetail } from "../../components/ListDetail";
import { LoadProblem } from "../../components/LoadProblem";
import { UnsavedBar } from "../../components/UnsavedBar";
import { useApi } from "../../hooks/useApi";
import { useGuardedSelection } from "../../hooks/useGuardedSelection";
import { useT } from "../../i18n/LanguageContext";
import { GeneralNoteForm } from "./GeneralNoteForm";
import styles from "./MemoryPage.module.css";

// A note we want to open again once the list has reloaded. Its id changed, so we look for it by content.
interface WantedNote {
  authorId: string;
  subjectId: string;
  text: string;
  /** The list as it was when we started waiting. The note can only be in a newer list. */
  oldList: GeneralNote[] | null;
}

// The bot keeps a note on one line with single spaces; compare texts the same way.
const oneLine = (text: string) => text.trim().replace(/\s+/g, " ");

/** The General notes tab: what people said about other people (opinions, not facts). */
export function GeneralTab({ serverId }: { serverId: string }) {
  const t = useT();
  const notes = useApi(() => listGeneral(serverId), [serverId]);
  const selection = useGuardedSelection();
  const [wanted, setWanted] = useState<WantedNote | null>(null);
  const { jumpTo } = selection;

  // After an edit, the list comes back with the note under a new id: find it and select it again.
  useEffect(() => {
    if (wanted === null || !notes.data || notes.data === wanted.oldList) return;
    const found = notes.data.find(
      (note) => note.author_id === wanted.authorId && note.subject_id === wanted.subjectId && note.text === wanted.text,
    );
    if (found) jumpTo(found.id);
    setWanted(null);
  }, [notes.data, wanted, jumpTo]);

  if (notes.error && !notes.data) return <LoadProblem error={notes.error} onRetry={notes.reload} />;
  if (!notes.data) return <p className="muted">{t("common.loading")}</p>;

  const selected = notes.data.find((note) => note.id === selection.selected) ?? null;

  const afterSave = (note: GeneralNote, newText: string) => {
    setWanted({ authorId: note.author_id, subjectId: note.subject_id, text: oneLine(newText), oldList: notes.data });
    selection.setDirty(false);
    notes.reload();
  };

  const afterDelete = () => {
    selection.jumpTo(null);
    notes.reload();
  };

  const renderNote = (note: GeneralNote) => (
    <>
      <div className={styles.rowTitle}>
        {note.author_name} → {note.subject_name}
      </div>
      <div className={styles.rowText}>{note.text}</div>
    </>
  );

  return (
    <ListDetail
      items={notes.data}
      getKey={(note) => note.id}
      renderItem={renderNote}
      selectedKey={selection.selected}
      onSelect={selection.select}
      emptyText={t("memory.general.empty")}
      detail={
        selected === null ? null : (
          <>
            {selection.askingToDiscard && (
              <UnsavedBar onDiscard={selection.discard} onKeepEditing={selection.keepEditing} />
            )}
            <GeneralNoteForm
              key={selected.id}
              serverId={serverId}
              note={selected}
              onSaved={(newText) => afterSave(selected, newText)}
              onDeleted={afterDelete}
              onDirtyChange={selection.setDirty}
            />
          </>
        )
      }
    />
  );
}
