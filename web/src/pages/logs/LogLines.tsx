import { useEffect, useRef, useState } from "react";
import type { LogLine } from "../../api/types";
import { useT } from "../../i18n/LanguageContext";
import styles from "./LogsPage.module.css";

const NEAR_BOTTOM_PX = 40;

/**
 * The scrolling box of log lines. Like a terminal, it follows new lines while you are at the bottom.
 * If you scrolled up to read something, it stays where you are and offers a "New lines" button instead.
 */
export function LogLines({ lines }: { lines: LogLine[] }) {
  const t = useT();
  const box = useRef<HTMLDivElement>(null);
  const atBottom = useRef(true);
  const [missedNewLines, setMissedNewLines] = useState(false);

  const scrollToBottom = () => {
    if (box.current) box.current.scrollTop = box.current.scrollHeight;
    atBottom.current = true;
    setMissedNewLines(false);
  };

  // Remember whether the user is at the bottom, every time they scroll.
  const onScroll = () => {
    const element = box.current;
    if (!element) return;
    atBottom.current = element.scrollHeight - element.scrollTop - element.clientHeight < NEAR_BOTTOM_PX;
    if (atBottom.current) setMissedNewLines(false);
  };

  // Runs after new lines were drawn.
  useEffect(() => {
    if (atBottom.current) scrollToBottom();
    else setMissedNewLines(true);
  }, [lines]);

  return (
    <div className={styles.logWrap}>
      <div className={styles.log} ref={box} onScroll={onScroll}>
        {lines.map((line, index) => (
          // The index is a fine key here: lines are only ever added at the end or dropped from the start.
          <div key={index} className={`${styles.line} ${line.kind === "system" ? styles.system : ""}`}>
            <span className={styles.time}>{line.time}</span>
            {line.place && <span className={styles.place}>{line.place}</span>}
            <span className={styles.text}>{line.text}</span>
          </div>
        ))}
      </div>
      {missedNewLines && (
        <button type="button" className={`primary ${styles.newLines}`} onClick={scrollToBottom}>
          ↓ {t("logs.newLines")}
        </button>
      )}
    </div>
  );
}
