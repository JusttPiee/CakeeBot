import { useCallback, useEffect, useState } from "react";
import { getBuildMemory, startBuildMemory } from "../../api/actions";
import { ApiError } from "../../api/client";
import type { BuildMemoryState } from "../../api/types";
import { ConfirmButton } from "../../components/ConfirmButton";
import { useT } from "../../i18n/LanguageContext";
import { errorMessage } from "../../utils/errorMessage";
import styles from "./LogsPage.module.css";

const CHECK_WHILE_RUNNING_MS = 3000;

interface BuildMemoryButtonProps {
  serverId: string;
  serverName: string;
}

/**
 * Runs !buildmemory for one server. It reads every channel and costs OpenAI tokens, so it warns first
 * and needs a second click. While a build runs, the button is locked and the state is checked every
 * 3 seconds; when it finishes, the bot's report is shown.
 */
export function BuildMemoryButton({ serverId, serverName }: BuildMemoryButtonProps) {
  const t = useT();
  const [state, setState] = useState<BuildMemoryState | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const running = state?.running ?? false;

  const check = useCallback(async () => {
    try {
      setState(await getBuildMemory(serverId));
    } catch {
      // The bot is away for a moment: the banner at the top already says so. Keep what we know.
    }
  }, [serverId]);

  // Once when the button appears, then only while a build is running.
  useEffect(() => {
    void check();
  }, [check]);

  useEffect(() => {
    if (!running) return;
    const timer = setInterval(() => void check(), CHECK_WHILE_RUNNING_MS);
    return () => clearInterval(timer);
  }, [running, check]);

  const start = async () => {
    setMessage(null);
    try {
      await startBuildMemory(serverId);
      setState((current) => ({ last_report: null, finished_at: null, ...current, running: true }));
    } catch (error) {
      const alreadyRunning = error instanceof ApiError && error.status === 409;
      setMessage(alreadyRunning ? t("build.alreadyRunning") : t("common.failed", { message: errorMessage(error) }));
      void check();
    }
  };

  return (
    <div className={styles.build}>
      <div className={styles.buildLine}>
        <ConfirmButton
          label={`🧠 ${t("build.button", { server: serverName })}`}
          confirmLabel={t("build.confirm")}
          onConfirm={() => void start()}
          disabled={running || state === null}
        />
        {running && (
          <span className={styles.buildLine}>
            <span className={styles.spinner} aria-hidden="true" />
            {t("build.running")}
          </span>
        )}
      </div>
      <p className="help">{t("build.warning")}</p>
      {message && (
        <p className="error-text" role="alert">
          {message}
        </p>
      )}
      {!running && state?.last_report && (
        <div>
          <p className="help">
            {t("build.lastReport", { time: state.finished_at ? new Date(state.finished_at).toLocaleString() : "" })}
          </p>
          <pre className={styles.report}>{state.last_report}</pre>
        </div>
      )}
    </div>
  );
}
