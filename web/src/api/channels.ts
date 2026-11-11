import { apiRequest } from "./client";
import type { ChannelInfo } from "./types";

/** Every text channel of the server, with whether AI mode is on there. */
export function listChannels(serverId: string): Promise<ChannelInfo[]> {
  return apiRequest<ChannelInfo[]>("GET", `/api/servers/${serverId}/channels`);
}

/** Turn AI mode on or off in one channel. It works right away, and nothing is posted in the channel. */
export async function setChannelAi(serverId: string, channelId: string, on: boolean): Promise<void> {
  await apiRequest("PUT", `/api/servers/${serverId}/channels/${channelId}/ai`, { on });
}
