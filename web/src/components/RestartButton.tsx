import { useStatus } from "../context/StatusContext";
import { useT } from "../i18n/LanguageContext";
import { ConfirmButton } from "./ConfirmButton";

/** Restarts the bot, after a second click to confirm. The banner at the top then shows the progress. */
export function RestartButton() {
  const t = useT();
  const { connection, restart } = useStatus();

  return (
    <ConfirmButton
      label={`↻ ${t("restart.button")}`}
      confirmLabel={t("restart.confirm")}
      onConfirm={() => void restart()}
      disabled={connection !== "ok"}
    />
  );
}
