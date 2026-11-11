// The shapes of the JSON the bot's API sends. They mirror the Ruby side (web_api/memory_views.rb and
// the routes), so the names are snake_case like there. Discord ids are always strings: they are too
// big for a JavaScript number.

// --- /api/status ---

export interface ServerInfo {
  id: string;
  name: string;
  icon_url: string | null;
}

export interface Status {
  bot_name: string;
  /** When the bot started. It changes after a restart, which is how the page knows the restart is done. */
  started_at: string;
  /** True when a saved setting only takes effect after a restart. */
  restart_needed: boolean;
  servers: ServerInfo[];
}

// --- Memory: people ---

/** One row in the list of people. */
export interface UserSummary {
  id: string;
  name: string;
  description: string;
  fact_count: number;
  personality_off: boolean;
}

/** Something a person asked Cake to remember. */
export interface Fact {
  id: string;
  date: string | null;
  text: string;
}

/** Everything Cake remembers about one person. */
export interface UserNote {
  id: string;
  name: string;
  description: string;
  personality: string;
  personality_off: boolean;
  facts: Fact[];
}

/** The part of a note the form can change. Facts are changed one by one, with their own calls. */
export interface UserNoteForm {
  description: string;
  personality: string;
  personality_off: boolean;
}

// --- Memory: the other tabs ---

/** What one person said about another (an opinion, not a fact). */
export interface GeneralNote {
  id: string;
  date: string;
  author_id: string;
  author_name: string;
  subject_id: string;
  subject_name: string;
  text: string;
}

export interface EventNote {
  /** The event's file name, made from its title. It changes when the title changes. */
  slug: string;
  title: string;
  /** "2026-11-21" or "2026-11-21 20:00" */
  when: string;
  details: string;
  past: boolean;
}

export interface EventForm {
  title: string;
  when: string;
  details: string;
}

/** The rolling summary Cake keeps of one AI channel. */
export interface ChannelSummary {
  channel_id: string;
  /** "" when the channel no longer exists. */
  channel_name: string;
  updated: string;
  text: string;
}

/** One line of the shared recent memory: a question to Cake with its answer, or another bot tagging Cake. */
export interface RecentEntry {
  kind: "exchange" | "tagged";
  time: string;
  channel_id: string;
  channel_name: string;
  /** False for a channel not everyone can read: Cake only uses the line in that same channel. */
  public: boolean;
  speaker_id: string;
  speaker_name: string;
  text: string;
  /** Cake's answer, or null when Cake did not answer (kind "tagged"). */
  answer: string | null;
}

// --- AI channels ---

export interface ChannelInfo {
  id: string;
  name: string;
  ai_on: boolean;
  /** False when Cake has no permission to read the channel, so AI mode can't work there. */
  readable: boolean;
}

// --- Config ---

export type ConfigValue = number | string;

export interface ConfigField {
  /** The constant's name in config.rb, e.g. "MAX_HISTORY_MESSAGES". */
  name: string;
  type: "integer" | "choice";
  min: number | null;
  max: number | null;
  options: string[] | null;
  default: ConfigValue;
  /** The value in settings.json, or null when the default is used. */
  saved: ConfigValue | null;
  /** The value the bot is using right now (until the next restart). */
  running: ConfigValue;
}

export interface ConfigGroup {
  id: string;
  fields: ConfigField[];
}

export interface ConfigData {
  restart_needed: boolean;
  read_only: { name: string; value: ConfigValue | null }[];
  groups: ConfigGroup[];
}

// --- Logs ---

export interface LogLine {
  /** "14:02:11", or "" for a line without a timestamp. */
  time: string;
  kind: "chat" | "system";
  /** For chat lines: "Server #channel" or "DM". "" for system lines. */
  place: string;
  text: string;
}

export interface LogPage {
  /** How many lines the day has now. Send it back as "after" to get only newer lines. */
  cursor: number;
  lines: LogLine[];
}

// --- Commands ---

export interface BuildMemoryState {
  running: boolean;
  last_report: string | null;
  finished_at: string | null;
}
