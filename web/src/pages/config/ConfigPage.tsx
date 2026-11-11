import { useEffect, useRef, useState } from "react";
import { ApiError } from "../../api/client";
import { getConfig, saveConfig } from "../../api/config";
import type { ConfigData, ConfigValue } from "../../api/types";
import { LoadProblem } from "../../components/LoadProblem";
import { useToast } from "../../components/Toast";
import { useStatus } from "../../context/StatusContext";
import { useApi } from "../../hooks/useApi";
import { useT } from "../../i18n/LanguageContext";
import type { TextKey } from "../../i18n/en";
import { errorMessage } from "../../utils/errorMessage";
import { ConfigField } from "./ConfigField";
import styles from "./ConfigPage.module.css";
import { parseValue, savedValue } from "./configValues";
import { RestartBanner } from "./RestartBanner";

/**
 * The Config page: every setting the bot lets us change, in groups, with one Save button.
 * A setting only takes effect after a restart (the bot reads its settings once, when it starts),
 * so after saving, a banner offers to restart.
 */
export function ConfigPage() {
  const t = useT();
  const toast = useToast();
  const { status, refresh } = useStatus();
  const loaded = useApi(getConfig, []);
  // The config on screen: what was loaded, or what the bot answered after the last save.
  const [config, setConfig] = useState<ConfigData | null>(null);
  // Only the boxes that were touched: setting name => what is typed in it now.
  const [edits, setEdits] = useState<Record<string, string>>({});
  const [serverErrors, setServerErrors] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (loaded.data) setConfig(loaded.data);
  }, [loaded.data]);

  // When the bot has restarted (its start time changed), load the config again: the "running" values are new.
  const startedAt = status?.started_at;
  const lastStartedAt = useRef(startedAt);
  const { reload } = loaded;
  useEffect(() => {
    if (startedAt === lastStartedAt.current) return;
    lastStartedAt.current = startedAt;
    reload();
  }, [startedAt, reload]);

  if (loaded.error && config === null) return <LoadProblem error={loaded.error} onRetry={loaded.reload} />;
  if (config === null) return <p className="muted">{t("common.loading")}</p>;

  const fields = config.groups.flatMap((group) => group.fields);
  const typedIn = (name: string, fallback: ConfigValue) => edits[name] ?? String(fallback);

  // Work out, from what is typed, which settings really changed and whether any box is invalid.
  const changes: Record<string, ConfigValue> = {};
  let anyInvalid = false;
  for (const field of fields) {
    const value = parseValue(field, typedIn(field.name, savedValue(field)));
    if (value === null) anyInvalid = true;
    else if (value !== savedValue(field)) changes[field.name] = value;
  }
  const canSave = Object.keys(changes).length > 0 && !anyInvalid && !busy;

  const changeField = (name: string, typed: string) => {
    setEdits((current) => ({ ...current, [name]: typed }));
    setServerErrors((current) => Object.fromEntries(Object.entries(current).filter(([key]) => key !== name)));
  };

  const save = async () => {
    setBusy(true);
    try {
      setConfig(await saveConfig(changes));
      setEdits({});
      setServerErrors({});
      toast(t("common.saved"));
      refresh(); // the sidebar shows its "restart needed" dot from the status
    } catch (error) {
      showSaveProblem(error);
    } finally {
      setBusy(false);
    }
  };

  // The bot refused some values: show each message at its setting and bring the first one into view.
  const showSaveProblem = (error: unknown) => {
    const fieldErrors = error instanceof ApiError ? error.fieldErrors : null;
    if (fieldErrors === null) return toast(t("common.failed", { message: errorMessage(error) }), "error");

    setServerErrors(fieldErrors);
    const first = document.getElementById(`config-${Object.keys(fieldErrors)[0]}`);
    first?.scrollIntoView?.({ block: "center" });
  };

  return (
    <>
      <h1>{t("config.title")}</h1>
      <p className="muted">{t("config.intro")}</p>
      {config.restart_needed && <RestartBanner />}

      {config.groups.map((group) => (
        <section key={group.id} className={styles.group}>
          <h2>{t(`config.group.${group.id}` as TextKey)}</h2>
          {group.fields.map((field) => (
            <ConfigField
              key={field.name}
              field={field}
              typed={typedIn(field.name, savedValue(field))}
              serverError={serverErrors[field.name] ?? null}
              onChange={(typed) => changeField(field.name, typed)}
            />
          ))}
        </section>
      ))}

      <div className={styles.saveBar}>
        <button type="button" className="primary" disabled={!canSave} onClick={() => void save()}>
          {t("common.save")}
        </button>
      </div>

      <section className={styles.group}>
        <h2>{t("config.envTitle")}</h2>
        <p className="help">{t("config.envHelp")}</p>
        <dl className={styles.envList}>
          {config.read_only.map((setting) => (
            <div key={setting.name} style={{ display: "contents" }}>
              <dt>
                <code>{setting.name}</code>
              </dt>
              <dd>{setting.value ?? <span className="muted">{t("config.notSet")}</span>}</dd>
            </div>
          ))}
        </dl>
      </section>
    </>
  );
}
