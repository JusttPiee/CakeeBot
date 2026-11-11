import { useEffect, useState } from "react";
import { deleteEvent, saveEvent } from "../../api/memory";
import type { EventNote } from "../../api/types";
import { ConfirmButton } from "../../components/ConfirmButton";
import { DetailPanel, DetailSection } from "../../components/DetailPanel";
import { useToast } from "../../components/Toast";
import { useT } from "../../i18n/LanguageContext";
import { errorMessage } from "../../utils/errorMessage";
import { rowsFor } from "../../utils/rowsFor";

// "2026-11-21" or "2026-11-21 20:00". The bot checks again, and also refuses dates like February 30th.
const WHEN_FORMAT = /^\d{4}-\d{2}-\d{2}( \d{2}:\d{2})?$/;

interface EventFormProps {
  serverId: string;
  event: EventNote;
  /** Called with the event's slug after saving. It is a new slug when the title changed. */
  onSaved: (slug: string) => void;
  onDeleted: () => void;
  onDirtyChange?: (dirty: boolean) => void;
}

/** The form for one planned event. The time is checked here first, so mistakes show while typing. */
export function EventForm({ serverId, event, onSaved, onDeleted, onDirtyChange }: EventFormProps) {
  const t = useT();
  const toast = useToast();
  const [title, setTitle] = useState(event.title);
  const [when, setWhen] = useState(event.when);
  const [details, setDetails] = useState(event.details);
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<string | null>(null);

  const dirty = title !== event.title || when !== event.when || details !== event.details;
  const whenLooksRight = WHEN_FORMAT.test(when.trim());
  const canSave = dirty && whenLooksRight && title.trim() !== "" && !busy;

  useEffect(() => {
    onDirtyChange?.(dirty);
  }, [dirty, onDirtyChange]);

  const save = async () => {
    setBusy(true);
    setProblem(null);
    try {
      const saved = await saveEvent(serverId, event.slug, { title, when: when.trim(), details });
      toast(t("common.saved"));
      onSaved(saved.slug);
    } catch (error) {
      setProblem(errorMessage(error));
    } finally {
      setBusy(false);
    }
  };

  const remove = async () => {
    setBusy(true);
    try {
      await deleteEvent(serverId, event.slug);
      toast(t("common.deleted"));
      onDeleted();
    } catch (error) {
      setProblem(errorMessage(error));
      setBusy(false);
    }
  };

  return (
    <DetailPanel>
      <DetailSection>
        <div className="field">
          <label htmlFor="event-title">{t("memory.events.title")}</label>
          <input id="event-title" value={title} onChange={(change) => setTitle(change.target.value)} />
        </div>

        <div className="field">
          <label htmlFor="event-when">{t("memory.events.when")}</label>
          <input
            id="event-when"
            value={when}
            placeholder="2026-11-21 20:00"
            aria-invalid={!whenLooksRight}
            onChange={(change) => setWhen(change.target.value)}
          />
          <p className={whenLooksRight ? "help" : "error-text"}>{t("memory.events.whenHelp")}</p>
        </div>

        <div className="field">
          <label htmlFor="event-details">{t("memory.events.details")}</label>
          <textarea
            id="event-details"
            value={details}
            rows={rowsFor(details)}
            onChange={(change) => setDetails(change.target.value)}
          />
        </div>

        {problem && (
          <p className="error-text" role="alert">
            {problem}
          </p>
        )}
        <div className="actions">
          <button type="button" className="primary" disabled={!canSave} onClick={() => void save()}>
            {t("common.save")}
          </button>
        </div>
      </DetailSection>

      <DetailSection>
        <div className="actions">
          <ConfirmButton
            label={t("memory.events.delete")}
            confirmLabel={t("memory.events.deleteConfirm")}
            onConfirm={() => void remove()}
            danger
            disabled={busy}
          />
        </div>
      </DetailSection>
    </DetailPanel>
  );
}
