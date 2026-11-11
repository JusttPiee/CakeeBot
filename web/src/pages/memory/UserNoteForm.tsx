import { useEffect, useState } from "react";
import { deleteUser, saveUser } from "../../api/memory";
import type { UserNote } from "../../api/types";
import { ConfirmButton } from "../../components/ConfirmButton";
import { DetailSection } from "../../components/DetailPanel";
import { useToast } from "../../components/Toast";
import { Toggle } from "../../components/Toggle";
import { useT } from "../../i18n/LanguageContext";
import { errorMessage } from "../../utils/errorMessage";
import { rowsFor } from "../../utils/rowsFor";

interface UserNoteFormProps {
  serverId: string;
  note: UserNote;
  /** Called with the note as the bot saved it. */
  onSaved: (note: UserNote) => void;
  onDeleted: () => void;
  /** Tells the parent whether there are changes that have not been saved yet. */
  onDirtyChange?: (dirty: boolean) => void;
}

/**
 * The form for the part of a note that is plain text: description, personality, and the off switch.
 * (The remembered facts have their own component, FactList, because each fact is saved on its own.)
 *
 * The inputs are "controlled": React state holds what is typed, and each input shows that state.
 */
export function UserNoteForm({ serverId, note, onSaved, onDeleted, onDirtyChange }: UserNoteFormProps) {
  const t = useT();
  const toast = useToast();
  const [description, setDescription] = useState(note.description);
  const [personality, setPersonality] = useState(note.personality);
  const [personalityOff, setPersonalityOff] = useState(note.personality_off);
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<string | null>(null);

  // "Dirty" = the form differs from what is saved. Worked out on every render, not stored.
  const dirty =
    description !== note.description || personality !== note.personality || personalityOff !== note.personality_off;

  useEffect(() => {
    onDirtyChange?.(dirty);
  }, [dirty, onDirtyChange]);

  const save = async () => {
    setBusy(true);
    setProblem(null);
    try {
      const saved = await saveUser(serverId, note.id, { description, personality, personality_off: personalityOff });
      // The bot may tidy the text (one line, no headings), so show exactly what it kept.
      setDescription(saved.description);
      setPersonality(saved.personality);
      setPersonalityOff(saved.personality_off);
      toast(t("common.saved"));
      onSaved(saved);
    } catch (error) {
      setProblem(t("common.failed", { message: errorMessage(error) }));
    } finally {
      setBusy(false);
    }
  };

  const remove = async () => {
    setBusy(true);
    try {
      await deleteUser(serverId, note.id);
      toast(t("common.deleted"));
      onDeleted();
    } catch (error) {
      setProblem(t("common.failed", { message: errorMessage(error) }));
      setBusy(false);
    }
  };

  return (
    <>
      <DetailSection>
        <div className="field">
          <label htmlFor="note-description">{t("memory.note.description")}</label>
          <input
            id="note-description"
            value={description}
            disabled={personalityOff}
            onChange={(event) => setDescription(event.target.value)}
          />
          <p className="help">{t("memory.note.descriptionHelp")}</p>
        </div>

        <div className="field">
          <label htmlFor="note-personality">{t("memory.note.personality")}</label>
          <textarea
            id="note-personality"
            value={personality}
            rows={rowsFor(personality)}
            disabled={personalityOff}
            onChange={(event) => setPersonality(event.target.value)}
          />
          <p className="help">{t("memory.note.personalityHelp")}</p>
        </div>

        <div className="field switch-row">
          <Toggle checked={personalityOff} onChange={setPersonalityOff} label={t("memory.note.personalityOff")} />
          <div>
            <div>{t("memory.note.personalityOff")}</div>
            <p className="help">{t("memory.note.personalityOffHelp")}</p>
          </div>
        </div>
        {personalityOff && !note.personality_off && <p className="warning-text">{t("memory.note.offWarning")}</p>}

        {problem && (
          <p className="error-text" role="alert">
            {problem}
          </p>
        )}
        <div className="actions">
          <button type="button" className="primary" disabled={!dirty || busy} onClick={() => void save()}>
            {t("common.save")}
          </button>
        </div>
      </DetailSection>

      <DetailSection>
        <div className="actions">
          <ConfirmButton
            label={t("memory.note.delete")}
            confirmLabel={t("memory.note.deleteConfirm")}
            onConfirm={() => void remove()}
            danger
            disabled={busy}
          />
          <span className="help">{t("memory.note.deleteHelp")}</span>
        </div>
      </DetailSection>
    </>
  );
}
