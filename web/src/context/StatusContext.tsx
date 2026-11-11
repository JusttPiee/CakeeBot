import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { restartBot } from "../api/actions";
import { ApiError } from "../api/client";
import { getStatus } from "../api/status";
import type { Status } from "../api/types";

/**
 * How the page and the bot are doing:
 *   ok           the bot answers
 *   reconnecting the bot stopped answering (it was closed, or the computer is busy)
 *   restarting   we asked for a restart and are waiting for the new bot
 *   stopped      we asked for a restart, but no new bot showed up in time
 */
export type Connection = "ok" | "reconnecting" | "restarting" | "stopped";

interface StatusContextValue {
  /** The last status the bot gave. It stays while the bot is unreachable, so the page doesn't go blank. */
  status: Status | null;
  connection: Connection;
  /** True when the bot refused our token: the page must ask for the link from the terminal. */
  needsToken: boolean;
  /** Ask the bot for its status right now (e.g. after saving settings). */
  refresh: () => void;
  /** Restart the bot and follow it until the new one is up. */
  restart: () => Promise<void>;
}

const StatusContext = createContext<StatusContextValue | null>(null);

const TICK_MS = 1000; // while something is wrong, ask every second
const TICKS_BETWEEN_CHECKS_WHEN_OK = 5; // while all is well, every 5 seconds is enough
const RESTART_GIVE_UP_MS = 30_000;

// What we remember while a restart is under way
interface RestartWatch {
  /** started_at of the bot we asked to restart. A different value means the new bot is answering. */
  oldStartedAt: string | null;
  askedAt: number;
}

/** Wrap the app in this once (see App.tsx). It keeps asking the bot for its status. */
export function StatusProvider({ children }: { children: ReactNode }) {
  const [status, setStatus] = useState<Status | null>(null);
  const [connection, setConnection] = useState<Connection>("ok");
  const [needsToken, setNeedsToken] = useState(false);

  // Refs are values that survive between renders but, unlike state, don't cause a render when
  // they change. The timer below needs the latest values without being restarted each time.
  const connectionRef = useRef<Connection>("ok");
  const restartWatch = useRef<RestartWatch | null>(null);
  const ticksSinceCheck = useRef(0);
  const checking = useRef(false);

  const changeConnection = useCallback((next: Connection) => {
    connectionRef.current = next;
    setConnection(next);
  }, []);

  // While a restart is under way: still waiting, or has it taken too long?
  const stillRestarting = useCallback(() => {
    const waited = Date.now() - (restartWatch.current?.askedAt ?? 0);
    changeConnection(waited > RESTART_GIVE_UP_MS ? "stopped" : "restarting");
  }, [changeConnection]);

  const check = useCallback(async () => {
    if (checking.current) return; // the previous question is still unanswered
    checking.current = true;
    ticksSinceCheck.current = 0;
    try {
      const fresh = await getStatus();
      const watch = restartWatch.current;
      if (watch && fresh.started_at === watch.oldStartedAt) {
        stillRestarting(); // the old bot answered: it has not gone down yet
        return;
      }
      restartWatch.current = null;
      setStatus(fresh);
      setNeedsToken(false);
      changeConnection("ok");
    } catch (problem) {
      if (problem instanceof ApiError && problem.status === 401) {
        setNeedsToken(true);
      } else if (restartWatch.current) {
        stillRestarting();
      } else {
        changeConnection("reconnecting");
      }
    } finally {
      checking.current = false;
    }
  }, [changeConnection, stillRestarting]);

  // Ask once when the page opens, then keep asking: slowly while all is well, every second otherwise.
  useEffect(() => {
    void check();
    const timer = setInterval(() => {
      ticksSinceCheck.current += 1;
      const allIsWell = connectionRef.current === "ok";
      if (allIsWell && ticksSinceCheck.current < TICKS_BETWEEN_CHECKS_WHEN_OK) return;
      void check();
    }, TICK_MS);
    return () => clearInterval(timer); // the cleanup: runs when the provider leaves the page
  }, [check]);

  const restart = useCallback(async () => {
    restartWatch.current = { oldStartedAt: status?.started_at ?? null, askedAt: Date.now() };
    changeConnection("restarting");
    try {
      await restartBot();
    } catch (problem) {
      // 409 = a restart was already requested: keep waiting for it. Anything else: the timer will sort it out.
      if (!(problem instanceof ApiError && problem.status === 409)) void check();
    }
  }, [status, changeConnection, check]);

  const refresh = useCallback(() => void check(), [check]);

  const value = useMemo(
    () => ({ status, connection, needsToken, refresh, restart }),
    [status, connection, needsToken, refresh, restart],
  );
  return <StatusContext.Provider value={value}>{children}</StatusContext.Provider>;
}

export function useStatus(): StatusContextValue {
  const value = useContext(StatusContext);
  if (value === null) throw new Error("useStatus must be used inside <StatusProvider>");
  return value;
}
