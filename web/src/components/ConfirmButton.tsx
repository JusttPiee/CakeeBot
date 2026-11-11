import { useEffect, useState } from "react";
import { useT } from "../i18n/LanguageContext";
import styles from "./ConfirmButton.module.css";

interface ConfirmButtonProps {
  /** The button's normal text, e.g. "Delete note". */
  label: string;
  /** The text of the second button that really does it, e.g. "Yes, delete". */
  confirmLabel: string;
  onConfirm: () => void;
  /** Red, for actions that delete something. */
  danger?: boolean;
  disabled?: boolean;
  /** For a label that is only an icon: what screen readers should say instead. */
  ariaLabel?: string;
  /** No background until it is clicked, for a small icon button inside a row. */
  quiet?: boolean;
}

const BACK_TO_NORMAL_MS = 4000;

/**
 * A button that asks "are you sure?" inside the page: the first click turns it into
 * a confirm button and a Cancel button. (The browser's own confirm() popup is not used.)
 * If nothing is clicked for a few seconds it goes back to normal, so it can't be hit by accident later.
 */
export function ConfirmButton(props: ConfirmButtonProps) {
  const { label, confirmLabel, onConfirm, danger = false, disabled = false, ariaLabel, quiet = false } = props;
  const t = useT();
  const [asking, setAsking] = useState(false);

  useEffect(() => {
    if (!asking) return;
    const timer = setTimeout(() => setAsking(false), BACK_TO_NORMAL_MS);
    return () => clearTimeout(timer);
  }, [asking]);

  if (!asking) {
    return (
      <button
        type="button"
        className={quiet ? styles.quiet : danger ? "danger" : ""}
        aria-label={ariaLabel}
        disabled={disabled}
        onClick={() => setAsking(true)}
      >
        {label}
      </button>
    );
  }

  const confirm = () => {
    setAsking(false);
    onConfirm();
  };

  return (
    <span className={styles.asking}>
      <button type="button" className={danger ? "danger" : "primary"} onClick={confirm}>
        {confirmLabel}
      </button>
      <button type="button" onClick={() => setAsking(false)}>
        {t("common.cancel")}
      </button>
    </span>
  );
}
