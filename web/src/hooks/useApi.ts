import { useCallback, useEffect, useRef, useState } from "react";
import { ApiError } from "../api/client";

/** What a component gets back from useApi. */
export interface ApiState<T> {
  /** The loaded data, or null while the first load is running (or after it failed). */
  data: T | null;
  error: ApiError | null;
  loading: boolean;
  /** Load again, e.g. after saving. The old data stays on screen until the new data arrives. */
  reload: () => void;
}

/**
 * Loads data from the bot when a component appears, and again whenever `deps` change.
 *
 *   const { data: people } = useApi(() => listUsers(serverId), [serverId]);
 *
 * A "hook" is a function whose name starts with "use" and that may remember things between
 * renders (here: the data). This one hides the usual loading / error / reload bookkeeping.
 */
export function useApi<T>(load: () => Promise<T>, deps: unknown[]): ApiState<T> {
  const [data, setData] = useState<T | null>(null);
  const [error, setError] = useState<ApiError | null>(null);
  const [loading, setLoading] = useState(true);
  const [reloadCount, setReloadCount] = useState(0);
  const lastReloadCount = useRef(0);

  useEffect(() => {
    // Did we get here because of reload(), or because the deps changed (e.g. another server)?
    const isReload = reloadCount !== lastReloadCount.current;
    lastReloadCount.current = reloadCount;
    if (!isReload) setData(null); // other deps = other data: never show the old one under a new title

    // If the deps change again before this load finishes, its answer must be thrown away.
    let outdated = false;
    setLoading(true);
    load()
      .then((loaded) => {
        if (outdated) return;
        setData(loaded);
        setError(null);
        setLoading(false);
      })
      .catch((problem: unknown) => {
        if (outdated) return;
        setError(toApiError(problem));
        setLoading(false);
      });

    return () => {
      outdated = true;
    };
    // `load` is a new function on every render, so it can't be in the list: the caller's deps say when to reload.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [...deps, reloadCount]);

  const reload = useCallback(() => setReloadCount((count) => count + 1), []);

  return { data, error, loading, reload };
}

function toApiError(problem: unknown): ApiError {
  if (problem instanceof ApiError) return problem;
  return new ApiError(0, problem instanceof Error ? problem.message : "Something went wrong.");
}
