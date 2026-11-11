import { useCallback, useState } from "react";

/**
 * Remembers which item of a list is open, and protects unsaved changes:
 * while the open item's form is "dirty", picking another item does not switch right away.
 * Instead `askingToDiscard` turns true, and the page shows <UnsavedBar> to ask what to do.
 */
export function useGuardedSelection() {
  const [selected, setSelected] = useState<string | null>(null);
  const [waiting, setWaiting] = useState<string | null>(null); // the item the user wants to go to
  const [dirty, setDirty] = useState(false);

  const select = useCallback(
    (key: string) => {
      if (key === selected) return;
      if (dirty) setWaiting(key);
      else setSelected(key);
    },
    [selected, dirty],
  );

  /** Go to an item (or to nothing) without asking: used after a save or a delete. */
  const jumpTo = useCallback((key: string | null) => {
    setSelected(key);
    setWaiting(null);
    setDirty(false);
  }, []);

  const discard = useCallback(() => jumpTo(waiting), [jumpTo, waiting]);
  const keepEditing = useCallback(() => setWaiting(null), []);

  return { selected, askingToDiscard: waiting !== null, select, jumpTo, discard, keepEditing, setDirty };
}
