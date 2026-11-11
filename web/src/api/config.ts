import { apiRequest } from "./client";
import type { ConfigData, ConfigValue } from "./types";

/** Every setting the web UI may change, with its default, saved and running value. */
export function getConfig(): Promise<ConfigData> {
  return apiRequest<ConfigData>("GET", "/api/config");
}

/**
 * Saves the given settings to settings.json and returns the config as it is now.
 * If a value is not allowed, it throws an ApiError whose fieldErrors say which setting is wrong.
 */
export function saveConfig(values: Record<string, ConfigValue>): Promise<ConfigData> {
  return apiRequest<ConfigData>("PUT", "/api/config", { values });
}
