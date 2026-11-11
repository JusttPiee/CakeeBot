// Every text the app shows, in English. vi.ts has the same keys in Vietnamese.
// Components never contain text themselves: they ask for a key, e.g. t("common.save").
// {name} in a text is a variable, filled in by t("...", { name: value }).
import { configEn } from "./configTexts.en";

export const en = {
  // --- the frame around every page ---
  "app.title": "CakeeBot Admin",
  "nav.memory": "Memory",
  "nav.channels": "AI channels",
  "nav.config": "Config",
  "nav.logs": "Logs",
  "nav.restartNeeded": "restart needed",
  "server.label": "Server",
  "server.none": "Cake is not in any server yet.",
  "language.label": "Language",

  "restart.button": "Restart Cake",
  "restart.confirm": "Yes, restart",

  "connection.connecting": "Connecting to Cake…",
  "connection.reconnecting": "Can't reach Cake. Trying again…",
  "connection.restarting": "Cake is restarting…",
  "connection.stopped": "Cake did not come back. Start it again with start.bat.",

  "token.title": "This browser needs the link from Cake's terminal",
  "token.why": "The web UI only works with a secret link, so no other website can control your bot.",
  "token.how": "Look in the terminal where Cake is running. Near the top there is a line like this. Open that link once, and this browser will remember it.",
  "token.example": "First time in this browser? Open: http://localhost:4567/?token=…",

  // --- small words used everywhere ---
  "common.save": "Save",
  "common.cancel": "Cancel",
  "common.delete": "Delete",
  "common.edit": "Edit",
  "common.add": "Add",
  "common.reset": "Reset",
  "common.loading": "Loading…",
  "common.saved": "Saved",
  "common.deleted": "Deleted",
  "common.copy": "Copy",
  "common.copied": "Copied",
  "common.retry": "Try again",
  "common.loadFailed": "Could not load this: {message}",
  "common.failed": "That didn't work: {message}",
  "common.pickItem": "Pick something on the left to see it here.",
  "common.unsaved": "You have unsaved changes.",
  "common.discard": "Discard them",
  "common.keepEditing": "Keep editing",

  // --- Memory page ---
  "memory.title": "Memory",
  "memory.tab.people": "People",
  "memory.tab.general": "General notes",
  "memory.tab.events": "Events",
  "memory.tab.summaries": "Channels",

  "memory.people.count": "{count} people",
  "memory.people.search": "Search by name or ID",
  "memory.people.empty": "Cake has no notes about anyone in this server yet.",
  "memory.people.noMatch": "Nobody matches that search.",
  "memory.people.unnamed": "No name",
  "memory.people.optedOut": "opted out",
  "memory.people.facts": "{count} facts",

  "memory.note.userId": "User ID",
  "memory.note.description": "Description",
  "memory.note.descriptionHelp": "One line. Cake sees it in its list of people.",
  "memory.note.personality": "Personality",
  "memory.note.personalityHelp": "Cake's own notes about how this person talks and what they like.",
  "memory.note.personalityOff": "Personality notes off",
  "memory.note.personalityOffHelp": "When this is on, Cake writes no personality note about this person.",
  "memory.note.offWarning": "Saving will erase the personality text and description.",
  "memory.note.delete": "Delete note",
  "memory.note.deleteConfirm": "Yes, delete the whole note",
  "memory.note.deleteHelp": "Cake may write a new note about this person later.",

  "memory.facts.title": "Asked to remember",
  "memory.facts.empty": "Nothing yet.",
  "memory.facts.addPlaceholder": "Add something to remember…",
  "memory.facts.newLabel": "New fact",
  "memory.facts.editLabel": "Edit: {text}",
  "memory.facts.deleteLabel": "Delete: {text}",
  "memory.facts.deleteConfirm": "Delete?",

  "memory.general.empty": "Nobody has asked Cake to remember something about someone else yet.",
  "memory.general.from": "Said by",
  "memory.general.about": "About",
  "memory.general.date": "Date",
  "memory.general.text": "What they said",
  "memory.general.delete": "Delete note",
  "memory.general.deleteConfirm": "Yes, delete",

  "memory.events.empty": "No events are planned.",
  "memory.events.past": "past",
  "memory.events.title": "Title",
  "memory.events.when": "When",
  "memory.events.whenHelp": "Write it like 2026-11-21 or 2026-11-21 20:00.",
  "memory.events.details": "Details",
  "memory.events.delete": "Delete event",
  "memory.events.deleteConfirm": "Yes, delete",

  "memory.summaries.empty": "No channel has a summary yet. Cake writes one when an AI channel's chat gets long.",
  "memory.summaries.updated": "Updated {time}",
  "memory.summaries.unknownChannel": "Channel {id}",
  "memory.summaries.readOnly": "Cake rewrites this summary by itself, so it can't be edited here.",
  "memory.summaries.delete": "Delete summary",
  "memory.summaries.deleteConfirm": "Yes, delete",

  // --- AI channels page ---
  "channels.title": "AI channels",
  "channels.intro": "In these channels Cake answers every message. Switching here posts nothing in the channel.",
  "channels.count": "Channels with AI on: {count}",
  "channels.search": "Search channels",
  "channels.empty": "This server has no text channels Cake can see.",
  "channels.noMatch": "No channel matches that search.",
  "channels.unreadable": "Cake can't read this channel",
  "channels.toggle": "AI in {name}",
  "channels.on": "AI on",

  // --- Logs page ---
  "logs.title": "Logs",
  "logs.live": "Live",
  "logs.kindLabel": "Show",
  "logs.kind.all": "Everything",
  "logs.kind.chat": "Chat messages",
  "logs.kind.system": "System events",
  "logs.allServers": "All servers",
  "logs.dayLabel": "Day",
  "logs.search": "Search the log",
  "logs.shown": "{shown} of {total} lines",
  "logs.none": "There are no logs yet.",
  "logs.empty": "No log lines for this day.",
  "logs.noMatch": "No line matches the filters.",
  "logs.newLines": "New lines",

  "build.button": "Run !buildmemory for {server}",
  "build.confirm": "Yes, run it",
  "build.warning": "It reads old messages in every channel Cake can see and uses OpenAI tokens (one request per person).",
  "build.running": "!buildmemory is running…",
  "build.alreadyRunning": "!buildmemory is already running.",
  "build.lastReport": "Last run, finished {time}:",

  // --- Config page (its many texts live in configTexts.en.ts) ---
  ...configEn,
} as const;

/** Every key that exists. TypeScript refuses t("some.typo"), and refuses a vi.ts that misses a key. */
export type TextKey = keyof typeof en;
