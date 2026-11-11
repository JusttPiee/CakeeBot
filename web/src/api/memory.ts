// The calls behind the Memory page. One function per API route of the bot
// (see web_api/routes/user_note_routes.rb and memory_routes.rb).
import { apiRequest } from "./client";
import type { ChannelSummary, EventForm, EventNote, GeneralNote, UserNote, UserNoteForm, UserSummary } from "./types";

const serverPath = (serverId: string) => `/api/servers/${serverId}`;

// --- People ---

export function listUsers(serverId: string): Promise<UserSummary[]> {
  return apiRequest<UserSummary[]>("GET", `${serverPath(serverId)}/users`);
}

export function getUser(serverId: string, userId: string): Promise<UserNote> {
  return apiRequest<UserNote>("GET", `${serverPath(serverId)}/users/${userId}`);
}

/** Saves the form's three fields. The facts are never sent, so the bot's newest facts are always kept. */
export function saveUser(serverId: string, userId: string, form: UserNoteForm): Promise<UserNote> {
  return apiRequest<UserNote>("PUT", `${serverPath(serverId)}/users/${userId}`, form);
}

export async function deleteUser(serverId: string, userId: string): Promise<void> {
  await apiRequest("DELETE", `${serverPath(serverId)}/users/${userId}`);
}

// --- Facts and general notes (both are "memory items" with an id) ---

export async function addFact(serverId: string, userId: string, text: string): Promise<void> {
  await apiRequest("POST", `${serverPath(serverId)}/users/${userId}/facts`, { text });
}

/** Changes one fact or one general note. Its id changes too (the id is made from its text). */
export async function changeItem(serverId: string, itemId: string, text: string): Promise<void> {
  await apiRequest("PUT", `${serverPath(serverId)}/items/${itemId}`, { text });
}

export async function removeItem(serverId: string, itemId: string): Promise<void> {
  await apiRequest("DELETE", `${serverPath(serverId)}/items/${itemId}`);
}

export function listGeneral(serverId: string): Promise<GeneralNote[]> {
  return apiRequest<GeneralNote[]>("GET", `${serverPath(serverId)}/general`);
}

// --- Events ---

export function listEvents(serverId: string): Promise<EventNote[]> {
  return apiRequest<EventNote[]>("GET", `${serverPath(serverId)}/events`);
}

/** Returns the saved event. Its slug is new when the title changed. */
export function saveEvent(serverId: string, slug: string, form: EventForm): Promise<EventNote> {
  return apiRequest<EventNote>("PUT", `${serverPath(serverId)}/events/${encodeURIComponent(slug)}`, form);
}

export async function deleteEvent(serverId: string, slug: string): Promise<void> {
  await apiRequest("DELETE", `${serverPath(serverId)}/events/${encodeURIComponent(slug)}`);
}

// --- Channel summaries ---

export function listSummaries(serverId: string): Promise<ChannelSummary[]> {
  return apiRequest<ChannelSummary[]>("GET", `${serverPath(serverId)}/summaries`);
}

export async function deleteSummary(serverId: string, channelId: string): Promise<void> {
  await apiRequest("DELETE", `${serverPath(serverId)}/summaries/${channelId}`);
}
