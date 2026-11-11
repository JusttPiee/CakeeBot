import { useEffect, useState } from "react";
import { changeItem, removeItem } from "../../api/memory";
import type { GeneralNote } from "../../api/types";
import { ConfirmButton } from "../../components/ConfirmButton";
import { DetailPanel, DetailSection } from "../../components/DetailPanel";
import { useToast } from "../../components/Toast";
import { useT } from "../../i18n/LanguageContext";
import { errorMessage } from "../../utils/errorMessage";
import { rowsFor } from "../../utils/rowsFor";
import styles from "./MemoryPage.module.css";

interface GeneralNoteFormProps {
  serverId: string;
  note: GeneralNote;
  /** Called with the new text after saving. */
  onSaved: (newText: string) => void;
  onDeleted: () => void;
  onDirtyChange?: (dirty: boolean) => void;
}

/** One general note: who said it about whom (fixed), and the text (can be changed or deleted). */
export function GeneralNoteForm({ serverId, note, onSaved, onDeleted, onDirtyChange }: GeneralNoteFormProps) {
  const t = useT();
  const toast = useToast();
  const [text, setText] = useState(note.text);
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<string | null>(null);

  const dirty = text !== note.text;

  useEffect(() => {
    onDirtyChange?.(dirty);
  }, [dirty, onDirtyChange]);

  // Run a change, show a toast, then tell the parent. Problems are shown under the text box.
  const run = async (change: () => Promise<void>, doneText: string, afterwards: () => void) => {
    setBusy(true);
    setProblem(null);
    try {
      await change();
      toast(doneText);
      afterwards();
    } catch (error) {
      setProblem(errorMessage(error));
    } finally {
      setBusy(false);
    }
  };

  const save = () => run(() => changeItem(serverId, note.id, text), t("common.saved"), () => onSaved(text));
  const remove = () => run(() => removeItem(serverId, note.id), t("common.deleted"), onDeleted);

  return (
    <DetailPanel>
      <DetailSection>
        <dl className={styles.facts}>
          <dt>{t("memory.general.from")}</dt>
          <dd>{`${note.author_name} (${note.author_id})`}</dd>
          <dt>{t("memory.general.about")}</dt>
          <dd>{`${note.subject_name} (${note.subject_id})`}</dd>
          <dt>{t("memory.general.date")}</dt>
          <dd>{note.date}</dd>
        </dl>
      </DetailSection>

      <DetailSection>
        <div className="field">
          <label htmlFor="general-text">{t("memory.general.text")}</label>
          <textarea
            id="general-text"
            value={text}
            rows={rowsFor(text)}
            onChange={(change) => setText(change.target.value)}
          />
        </div>
        {problem && (
          <p className="error-text" role="alert">
            {problem}
          </p>
        )}
        <div className="actions">
          <button
            type="button"
            className="primary"
            disabled={!dirty || busy || text.trim() === ""}
            onClick={() => void save()}
          >
            {t("common.save")}
          </button>
          <ConfirmButton
            label={t("memory.general.delete")}
            confirmLabel={t("memory.general.deleteConfirm")}
            onConfirm={() => void remove()}
            danger
            disabled={busy}
          />
        </div>
      </DetailSection>
    </DetailPanel>
  );
}
