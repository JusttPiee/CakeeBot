import type { ReactNode } from "react";
import { useT } from "../i18n/LanguageContext";
import { EmptyState } from "./EmptyState";
import styles from "./ListDetail.module.css";

// <T> makes this component work for any kind of item (people, events, notes...):
// the page says how to get an item's key and how to draw its row.
interface ListDetailProps<T> {
  items: T[];
  getKey: (item: T) => string;
  renderItem: (item: T) => ReactNode;
  selectedKey: string | null;
  onSelect: (key: string) => void;
  /** What to show on the right for the selected item (usually a <DetailPanel>). null shows a "pick something" hint. */
  detail: ReactNode;
  /** Shown above the list, e.g. a search box. */
  toolbar?: ReactNode;
  /** Shown instead of the list when there are no items. */
  emptyText: string;
}

/** The layout of every Memory tab: a list on the left, the selected item on the right (like an email app). */
export function ListDetail<T>(props: ListDetailProps<T>) {
  const { items, getKey, renderItem, selectedKey, onSelect, detail, toolbar, emptyText } = props;
  const t = useT();

  return (
    <div className={styles.layout}>
      <div className={styles.listColumn}>
        {toolbar}
        {items.length === 0 ? (
          <EmptyState text={emptyText} />
        ) : (
          <ul className={styles.list}>
            {items.map((item) => {
              const key = getKey(item);
              const selected = key === selectedKey;
              return (
                <li key={key}>
                  <button
                    type="button"
                    className={`${styles.row} ${selected ? styles.selected : ""}`}
                    aria-current={selected}
                    onClick={() => onSelect(key)}
                  >
                    {renderItem(item)}
                  </button>
                </li>
              );
            })}
          </ul>
        )}
      </div>

      <div className={styles.detailColumn}>
        {detail === null ? <EmptyState text={t("common.pickItem")} /> : detail}
      </div>
    </div>
  );
}
