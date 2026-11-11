import { apiRequest } from "./client";
import type { BuildMemoryState } from "./types";

/** Ask the bot to restart. It answers first and restarts half a second later. */
export async function restartBot(): Promise<void> {
  await apiRequest<{ ok: boolean }>("POST", "/api/restart");
}

/** Is !buildmemory running in this server, and what did the last run report? */
export function getBuildMemory(serverId: string): Promise<BuildMemoryState> {
  return apiRequest<BuildMemoryState>("GET", `/api/servers/${serverId}/buildmemory`);
}

/** Start !buildmemory for this server. Throws an ApiError with status 409 if it is already running. */
export async function startBuildMemory(serverId: string): Promise<void> {
  await apiRequest<{ ok: boolean }>("POST", `/api/servers/${serverId}/buildmemory`);
}
