// The texts of the Config page, in English. Kept apart from en.ts because there are many:
// a label and a help line for each setting the bot lets the web UI change.
// The help lines say in plain words what the comments in the bot's config.rb say.
export const configEn = {
  "config.title": "Config",
  "config.intro": "Cake's limits. A change is saved to settings.json and takes effect after a restart.",
  "config.default": "Default: {value}",
  "config.running": "running: {value}",
  "config.resetLabel": "Reset {name}",
  "config.outOfRange": "Must be a whole number from {min} to {max}.",
  "config.restartBanner": "Saved. Restart Cake to apply the changes.",
  "config.restartNow": "Restart now",
  "config.envTitle": "Set in .env",
  "config.envHelp": "These are read from the .env file in the bot's folder and can't be changed here.",
  "config.notSet": "not set",

  "config.group.chat": "AI replies",
  "config.group.history": "Chat memory and compaction",
  "config.group.tools": "Tools",
  "config.group.search": "Searching memory and old messages",
  "config.group.buildmemory": "!buildmemory",
  "config.group.clear": "!clear",

  // --- AI replies ---
  "config.OPENAI_REASONING_EFFORT.label": "Thinking effort",
  "config.OPENAI_REASONING_EFFORT.help": "How much the model thinks before it replies. More thinking is slower and costs more.",
  "config.OPENAI_FALLBACK_REASONING_EFFORT.label": "Thinking effort for the retry",
  "config.OPENAI_FALLBACK_REASONING_EFFORT.help":
    "If thinking uses up the whole token budget and the reply comes back empty, Cake tries once more with this.",
  "config.OPENAI_MAX_OUTPUT_TOKENS.label": "Max tokens per reply",
  "config.OPENAI_MAX_OUTPUT_TOKENS.help": "Thinking and reply together. Only what is used is billed.",
  "config.MAX_TOOL_ROUNDS.label": "Tool rounds per reply",
  "config.MAX_TOOL_ROUNDS.help":
    "One round = the AI asks for tools, Cake runs them and sends the results back. After this many it must answer.",

  // --- Chat memory and compaction ---
  "config.MAX_HISTORY_MESSAGES.label": "Messages kept per channel",
  "config.MAX_HISTORY_MESSAGES.help":
    "The high mark. When a channel's chat memory goes over it, the oldest part is summarized and dropped.",
  "config.MAX_HISTORY_TOKENS.label": "Tokens kept per channel",
  "config.MAX_HISTORY_TOKENS.help": "The same high mark, counted in tokens. Whichever limit is reached first wins.",
  "config.COMPACT_TARGET_MESSAGES.label": "Messages left after compaction",
  "config.COMPACT_TARGET_MESSAGES.help": "The low mark the chat memory is cut down to. Must be below the high mark.",
  "config.COMPACT_TARGET_TOKENS.label": "Tokens left after compaction",
  "config.COMPACT_TARGET_TOKENS.help": "The same low mark, counted in tokens.",
  "config.HARD_MAX_HISTORY_MESSAGES.label": "Hard maximum of messages",
  "config.HARD_MAX_HISTORY_MESSAGES.help":
    "A safety net: if compaction keeps failing, the oldest messages are cut here without a summary. Must be above the high mark.",
  "config.HARD_MAX_HISTORY_TOKENS.label": "Hard maximum of tokens",
  "config.HARD_MAX_HISTORY_TOKENS.help": "The same safety net, counted in tokens.",
  "config.COMPACTION_REASONING_EFFORT.label": "Thinking effort for compaction",
  "config.COMPACTION_REASONING_EFFORT.help": "How much the model thinks while it writes a summary.",

  // --- Tools ---
  "config.SEARCH_MAX_RESULTS.label": "Results per web search",
  "config.SEARCH_MAX_RESULTS.help": "How many results one web search gives the AI.",
  "config.WEBPAGE_MAX_CHARS.label": "Characters read from a web page",
  "config.WEBPAGE_MAX_CHARS.help": "The AI gets at most this much text of a page (8,000 is about 2,000 tokens).",
  "config.IMAGE_MAX_PER_REPLY.label": "Images per reply",
  "config.IMAGE_MAX_PER_REPLY.help": "How many pictures the AI may look at for one reply. Each costs about 1,200 tokens.",
  "config.TEXT_FILE_MAX_PER_REPLY.label": "Text files per reply",
  "config.TEXT_FILE_MAX_PER_REPLY.help": "How many attached text files the AI may read for one reply.",

  // --- Searching ---
  "config.MEMORY_SEARCH_RESULTS.label": "Results per memory search",
  "config.MEMORY_SEARCH_RESULTS.help": "How many matching memories the AI gets back.",
  "config.CHANNEL_SEARCH_MAX_MESSAGES.label": "Messages read per channel search",
  "config.CHANNEL_SEARCH_MAX_MESSAGES.help": "How far back one search of a channel's old messages reads.",
  "config.CHANNEL_SEARCH_RESULTS.label": "Results per channel search",
  "config.CHANNEL_SEARCH_RESULTS.help": "How many old messages the AI gets back.",
  "config.CHANNEL_SEARCHES_PER_REPLY.label": "Channel searches per reply",
  "config.CHANNEL_SEARCHES_PER_REPLY.help": "Enough to try another date once or twice, but it keeps one reply quick.",

  // --- !buildmemory ---
  "config.BUILD_MEMORY_MESSAGES_PER_CHANNEL.label": "Messages read per channel",
  "config.BUILD_MEMORY_MESSAGES_PER_CHANNEL.help": "How far back !buildmemory reads in each channel.",
  "config.BUILD_MEMORY_MIN_MESSAGES.label": "Minimum messages per person",
  "config.BUILD_MEMORY_MIN_MESSAGES.help": "People with fewer messages are skipped: there is not enough to go on.",
  "config.BUILD_MEMORY_MAX_PEOPLE.label": "People per run",
  "config.BUILD_MEMORY_MAX_PEOPLE.help": "The most active people first. Each person is one request to OpenAI.",
  "config.BUILD_MEMORY_MAX_CHARS_PER_PERSON.label": "Characters read per person",
  "config.BUILD_MEMORY_MAX_CHARS_PER_PERSON.help": "Their newest messages, up to this much text (12,000 is about 3,000 tokens).",
  "config.BUILD_MEMORY_REASONING_EFFORT.label": "Thinking effort for !buildmemory",
  "config.BUILD_MEMORY_REASONING_EFFORT.help": "How much the model thinks while it writes a personality note.",

  // --- !clear ---
  "config.CLEAR_MAX_MESSAGES.label": "Messages deleted at most",
  "config.CLEAR_MAX_MESSAGES.help": "The most one !clear deletes. Discord itself allows at most 100.",
  "config.CLEAR_SCAN_MESSAGES.label": "Messages searched for one person",
  "config.CLEAR_SCAN_MESSAGES.help": "With !clear @user: how far back to look for that person's messages.",
  "config.CLEAR_REPORT_SECONDS.label": "Seconds the report stays",
  "config.CLEAR_REPORT_SECONDS.help": "The \"Deleted N messages\" note disappears after this long.",
} as const;
