import { AnimatePresence, motion } from "motion/react";
import { useState, type KeyboardEvent } from "react";
import { addFact, changeItem, removeItem } from "../../api/memory";
import type { Fact } from "../../api/types";
import { ConfirmButton } from "../../components/ConfirmButton";
import { DetailSection } from "../../components/DetailPanel";
import { useT } from "../../i18n/LanguageContext";
import { popRow } from "../../motion/presets";
import { errorMessage } from "../../utils/errorMessage";
import styles from "./FactList.module.css";

interface FactListProps {
  serverId: string;
  userId: string;
  facts: Fact[];
  /** Called after any fact was added, changed or removed, so the parent loads the note again. */
  onChanged: () => void;
}

/**
 * The things a person asked Cake to remember. Each one is saved the moment you press Enter or
 * confirm a delete: there is no Save button for the list, and the form's Save never touches it.
 */
export function FactList({ serverId, userId, facts, onChanged }: FactListProps) {
  const t = useT();
  const [newText, setNewText] = useState("");
  const [editingId, setEditingId] = useState<string | null>(null);
  const [editText, setEditText] = useState("");
  const [problem, setProblem] = useState<string | null>(null);

  // Run one change, then ask the parent to reload. Returns whether it worked.
  const run = async (change: () => Promise<void>): Promise<boolean> => {
    setProblem(null);
    try {
      await change();
      onChanged();
      return true;
    } catch (error) {
      setProblem(errorMessage(error));
      return false;
    }
  };

  const add = async () => {
    if (newText.trim() === "") return;
    if (await run(() => addFact(serverId, userId, newText.trim()))) setNewText("");
  };

  const startEditing = (fact: Fact) => {
    setEditingId(fact.id);
    setEditText(fact.text);
  };

  const saveEdit = async (fact: Fact) => {
    if (editText.trim() === "" || editText === fact.text) return setEditingId(null);
    if (await run(() => changeItem(serverId, fact.id, editText.trim()))) setEditingId(null);
  };

  const onEditKey = (event: KeyboardEvent, fact: Fact) => {
    if (event.key === "Enter") void saveEdit(fact);
    if (event.key === "Escape") setEditingId(null);
  };

  return (
    <DetailSection title={t("memory.facts.title")}>
      {facts.length === 0 && <p className="muted">{t("memory.facts.empty")}</p>}

      <ul className={styles.facts}>
        {/* AnimatePresence lets a removed fact slide out before it disappears */}
        <AnimatePresence initial={false}>
          {facts.map((fact) => (
            <motion.li key={fact.id} className={styles.fact} variants={popRow} initial="hidden" animate="shown" exit="gone">
              {fact.date && <span className={styles.date}>{fact.date}</span>}
              {editingId === fact.id ? (
                <input
                  autoFocus
                  value={editText}
                  aria-label={t("memory.facts.editLabel", { text: fact.text })}
                  onChange={(event) => setEditText(event.target.value)}
                  onKeyDown={(event) => onEditKey(event, fact)}
                  onBlur={() => setEditingId(null)}
                />
              ) : (
                <>
                  <span className={styles.text}>{fact.text}</span>
                  <button
                    type="button"
                    className={styles.icon}
                    aria-label={t("memory.facts.editLabel", { text: fact.text })}
                    onClick={() => startEditing(fact)}
                  >
                    ✏️
                  </button>
                  <ConfirmButton
                    label="🗑️"
                    ariaLabel={t("memory.facts.deleteLabel", { text: fact.text })}
                    confirmLabel={t("memory.facts.deleteConfirm")}
                    onConfirm={() => void run(() => removeItem(serverId, fact.id))}
                    danger
                    quiet
                  />
                </>
              )}
            </motion.li>
          ))}
        </AnimatePresence>
      </ul>

      <div className={styles.add}>
        <input
          value={newText}
          placeholder={t("memory.facts.addPlaceholder")}
          aria-label={t("memory.facts.newLabel")}
          onChange={(event) => setNewText(event.target.value)}
          onKeyDown={(event) => event.key === "Enter" && void add()}
        />
        <button type="button" disabled={newText.trim() === ""} onClick={() => void add()}>
          {t("common.add")}
        </button>
      </div>
      {problem && (
        <p className="error-text" role="alert">
          {problem}
        </p>
      )}
    </DetailSection>
  );
}
