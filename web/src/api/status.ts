import { apiRequest } from "./client";
import type { Status } from "./types";

/** Who the bot is, which servers it is in, and whether it needs a restart. */
export function getStatus(): Promise<Status> {
  return apiRequest<Status>("GET", "/api/status");
}
