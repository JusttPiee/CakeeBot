import type { ConfigField as Field } from "../../api/types";
import { useT } from "../../i18n/LanguageContext";
import type { TextKey } from "../../i18n/en";
import styles from "./ConfigPage.module.css";
import { parseValue, savedValue } from "./configValues";

interface ConfigFieldProps {
  field: Field;
  /** What is in the box right now, as text. */
  typed: string;
  /** What the bot said is wrong with this setting when saving, if anything. */
  serverError: string | null;
  onChange: (typed: string) => void;
}

/** One setting: its name, a box or a dropdown, what it does, and its default. */
export function ConfigField({ field, typed, serverError, onChange }: ConfigFieldProps) {
  const t = useT();
  const id = `config-${field.name}`;
  const label = t(`config.${field.name}.label` as TextKey);
  const invalid = parseValue(field, typed) === null;
  const differsFromDefault = typed !== String(field.default);
  const runningDiffers = field.running !== savedValue(field);

  return (
    <div className={styles.field}>
      <div className={styles.labelLine}>
        <label htmlFor={id}>{label}</label>
        {runningDiffers && <span className="badge">{t("config.running", { value: field.running })}</span>}
      </div>

      <div className={styles.inputLine}>
        {field.type === "choice" ? (
          <select id={id} value={typed} onChange={(event) => onChange(event.target.value)}>
            {(field.options ?? []).map((option) => (
              <option key={option} value={option}>
                {option}
              </option>
            ))}
          </select>
        ) : (
          <input
            id={id}
            value={typed}
            inputMode="numeric"
            aria-invalid={invalid || serverError !== null}
            onChange={(event) => onChange(event.target.value)}
          />
        )}
        <span className={styles.default}>{t("config.default", { value: field.default })}</span>
        {differsFromDefault && (
          <button
            type="button"
            className="link"
            aria-label={t("config.resetLabel", { name: label })}
            onClick={() => onChange(String(field.default))}
          >
            {t("common.reset")}
          </button>
        )}
      </div>

      {invalid && field.type === "integer" && (
        <p className="error-text">{t("config.outOfRange", { min: field.min ?? "", max: field.max ?? "" })}</p>
      )}
      {serverError && (
        <p className="error-text" role="alert">
          {serverError}
        </p>
      )}
      <p className="help">{t(`config.${field.name}.help` as TextKey)}</p>
      <code className={styles.constant}>{field.name}</code>
    </div>
  );
}
