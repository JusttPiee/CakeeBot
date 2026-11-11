import { useEffect, useRef, useState } from "react";
import { getLogs } from "../../api/logs";
import type { LogLine } from "../../api/types";
import { errorMessage } from "../../utils/errorMessage";

const POLL_MS = 2000;
const MAX_LINES = 5000; // the browser keeps at most this many; the oldest are dropped first

/**
 * The log lines of one day. With live = true it keeps asking the bot for new lines ("polling"):
 * every 2 seconds it sends the cursor it got last time and receives only what was written since.
 */
export function useLogLines(day: string | null, live: boolean) {
  const [lines, setLines] = useState<LogLine[]>([]);
  const [problem, setProblem] = useState<string | null>(null);
  const cursor = useRef<number | undefined>(undefined);

  useEffect(() => {
    if (day === null) return;

    // Another day: start from nothing.
    setLines([]);
    cursor.current = undefined;
    let stopped = false;
    let asking = false;

    const loadNewLines = async () => {
      if (asking) return; // the previous question is still unanswered (a slow moment): skip this round
      asking = true;
      try {
        const page = await getLogs(day, cursor.current);
        if (stopped) return;
        cursor.current = page.cursor;
        if (page.lines.length > 0) setLines((current) => [...current, ...page.lines].slice(-MAX_LINES));
        setProblem(null);
      } catch (error) {
        if (!stopped) setProblem(errorMessage(error));
      } finally {
        asking = false;
      }
    };

    void loadNewLines();
    const timer = live ? setInterval(() => void loadNewLines(), POLL_MS) : undefined;

    // The cleanup: runs when the day changes or the page is left. Without it the timer would run forever.
    return () => {
      stopped = true;
      clearInterval(timer);
    };
  }, [day, live]);

  return { lines, problem };
}
