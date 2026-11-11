import { expect, it } from "vitest";
import { en, type TextKey } from "./en";
import { vi as vietnamese } from "./vi";

// The settings the bot lets the web UI change: the same 27 names as CONFIG_GROUPS in web_api/config_fields.rb.
const CONFIG_NAMES = [
  "OPENAI_REASONING_EFFORT",
  "OPENAI_FALLBACK_REASONING_EFFORT",
  "OPENAI_MAX_OUTPUT_TOKENS",
  "MAX_TOOL_ROUNDS",
  "MAX_HISTORY_MESSAGES",
  "MAX_HISTORY_TOKENS",
  "COMPACT_TARGET_MESSAGES",
  "COMPACT_TARGET_TOKENS",
  "HARD_MAX_HISTORY_MESSAGES",
  "HARD_MAX_HISTORY_TOKENS",
  "COMPACTION_REASONING_EFFORT",
  "SEARCH_MAX_RESULTS",
  "WEBPAGE_MAX_CHARS",
  "IMAGE_MAX_PER_REPLY",
  "TEXT_FILE_MAX_PER_REPLY",
  "MEMORY_SEARCH_RESULTS",
  "CHANNEL_SEARCH_MAX_MESSAGES",
  "CHANNEL_SEARCH_RESULTS",
  "CHANNEL_SEARCHES_PER_REPLY",
  "BUILD_MEMORY_MESSAGES_PER_CHANNEL",
  "BUILD_MEMORY_MIN_MESSAGES",
  "BUILD_MEMORY_MAX_PEOPLE",
  "BUILD_MEMORY_MAX_CHARS_PER_PERSON",
  "BUILD_MEMORY_REASONING_EFFORT",
  "CLEAR_MAX_MESSAGES",
  "CLEAR_SCAN_MESSAGES",
  "CLEAR_REPORT_SECONDS",
];
const GROUPS = ["chat", "history", "tools", "search", "buildmemory", "clear"];

const dictionaries: Record<string, Record<string, string>> = { en, vi: vietnamese };

it("has a label and a help text for every setting, in both languages", () => {
  expect(CONFIG_NAMES).toHaveLength(27);
  for (const [language, dictionary] of Object.entries(dictionaries)) {
    for (const name of CONFIG_NAMES) {
      expect(dictionary[`config.${name}.label`], `${language} label of ${name}`).toBeTruthy();
      expect(dictionary[`config.${name}.help`], `${language} help of ${name}`).toBeTruthy();
    }
  }
});

it("has a title for every group, in both languages", () => {
  for (const dictionary of Object.values(dictionaries)) {
    for (const group of GROUPS) {
      expect(dictionary[`config.group.${group}`]).toBeTruthy();
    }
  }
});

it("has every English key in Vietnamese too", () => {
  const missing = (Object.keys(en) as TextKey[]).filter((key) => !vietnamese[key]);
  expect(missing).toEqual([]);
});
