import type { ApiError } from "../api/client";
import { useT } from "../i18n/LanguageContext";
import styles from "./EmptyState.module.css";

interface LoadProblemProps {
  error: ApiError;
  onRetry: () => void;
}

/** Shown in place of a list or a form when loading it failed. */
export function LoadProblem({ error, onRetry }: LoadProblemProps) {
  const t = useT();
  return (
    <div className={styles.empty} role="alert">
      <p>{t("common.loadFailed", { message: error.message })}</p>
      <button type="button" onClick={onRetry}>
        {t("common.retry")}
      </button>
    </div>
  );
}
