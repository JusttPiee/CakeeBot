import styles from "./EmptyState.module.css";

/** A quiet line for "there is nothing here (yet)". */
export function EmptyState({ text }: { text: string }) {
  return <p className={styles.empty}>{text}</p>;
}
