import { apiRequest } from "./client";
import type { LogPage } from "./types";

/** The days that have log files, newest first: ["2026-11-11", "2026-11-10"]. */
export function listLogDays(): Promise<string[]> {
  return apiRequest<string[]>("GET", "/api/logs/days");
}

/**
 * Log lines of one day. Without `after`: the last lines of the day.
 * With `after` (the cursor of the previous answer): only the lines written since then.
 */
export function getLogs(day: string, after?: number): Promise<LogPage> {
  const afterPart = after === undefined ? "" : `&after=${after}`;
  return apiRequest<LogPage>("GET", `/api/logs?day=${day}${afterPart}`);
}
