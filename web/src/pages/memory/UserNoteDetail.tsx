import { useEffect, useState } from "react";
import { getUser } from "../../api/memory";
import type { UserNote } from "../../api/types";
import { DetailPanel, DetailSection } from "../../components/DetailPanel";
import { LoadProblem } from "../../components/LoadProblem";
import { useToast } from "../../components/Toast";
import { useApi } from "../../hooks/useApi";
import { useT } from "../../i18n/LanguageContext";
import { FactList } from "./FactList";
import styles from "./MemoryPage.module.css";
import { UserNoteForm } from "./UserNoteForm";

interface UserNoteDetailProps {
  serverId: string;
  userId: string;
  /** The list on the left shows names, descriptions and fact counts, so it must reload after a change. */
  onListChanged: () => void;
  onDeleted: () => void;
  onDirtyChange: (dirty: boolean) => void;
}

/** The right side of the People tab: loads one person's note and shows its form and its facts. */
export function UserNoteDetail({ serverId, userId, onListChanged, onDeleted, onDirtyChange }: UserNoteDetailProps) {
  const t = useT();
  const toast = useToast();
  const loaded = useApi(() => getUser(serverId, userId), [serverId, userId]);
  // The note on screen: what was loaded, or what the bot just answered after a save (no need to load again).
  const [note, setNote] = useState<UserNote | null>(null);

  useEffect(() => {
    if (loaded.data) setNote(loaded.data);
  }, [loaded.data]);

  if (loaded.error && note === null) return <LoadProblem error={loaded.error} onRetry={loaded.reload} />;
  if (note === null) return <p className="muted">{t("common.loading")}</p>;

  const copyId = async () => {
    try {
      await navigator.clipboard.writeText(note.id);
      toast(t("common.copied"));
    } catch {
      // The browser refused (no permission): the id is on screen and can be selected by hand.
    }
  };

  const afterSave = (saved: UserNote) => {
    setNote(saved);
    onListChanged();
  };

  const afterFactChange = () => {
    loaded.reload();
    onListChanged();
  };

  return (
    <DetailPanel>
      <DetailSection>
        <h1>{note.name || t("memory.people.unnamed")}</h1>
        <div className={styles.idLine}>
          <span>{t("memory.note.userId")}</span>
          <code>{note.id}</code>
          <button type="button" className="link" onClick={() => void copyId()}>
            {t("common.copy")}
          </button>
        </div>
      </DetailSection>

      <UserNoteForm
        serverId={serverId}
        note={note}
        onSaved={afterSave}
        onDeleted={onDeleted}
        onDirtyChange={onDirtyChange}
      />
      <FactList serverId={serverId} userId={userId} facts={note.facts} onChanged={afterFactChange} />
    </DetailPanel>
  );
}
