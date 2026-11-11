# All bot settings in one place.
# - Settings read with `setting(...)` can be changed in .env (they are listed in .env.example).
# - Settings read with `saved_setting(...)` can be changed from the web UI. The value here is the default;
#   the web UI saves changes in settings.json, which wins over the default the next time the bot starts.
# - Plain constants are developer settings: change them here, in the code.
# Load this AFTER .env has been loaded (cakee.rb does that).

# Read a setting from .env / the environment, or use the default if it is empty
def setting(name, default:)
  value = ENV[name].to_s.strip
  value.empty? ? default : value
end

# --- settings.json: what the web UI changed ---
require 'json'

# Tests point this at a temp file, so they never read the real settings.
SETTINGS_FILE = ENV['CAKE_TEST_SETTINGS_FILE'] || File.join(__dir__, 'settings.json')
CONFIG_DEFAULTS = {} # name => default, for every setting the web UI may change

# { "MAX_HISTORY_MESSAGES" => 60 }. Empty if the file is missing, broken, or not a JSON object:
# a bad settings file must never stop the bot from starting.
def read_saved_settings(path)
  return {} unless File.file?(path)

  settings = JSON.parse(File.read(path, encoding: 'UTF-8'))
  settings.is_a?(Hash) ? settings : {}
rescue JSON::ParserError, SystemCallError
  {}
end

SAVED_SETTINGS = read_saved_settings(SETTINGS_FILE)

# The saved value if there is one of the right type (a number stays a number), or else the default.
def saved_setting(name, default, saved = SAVED_SETTINGS)
  CONFIG_DEFAULTS[name] = default
  value = saved[name]
  value.instance_of?(default.class) ? value : default
end

# --- Can be changed in .env ---
OPENAI_MODEL = setting('OPENAI_MODEL', default: 'gpt-6-luna') # change when OpenAI retires a model
temperature = setting('OPENAI_TEMPERATURE', default: nil) # e.g. "0.7", or nil = model's default
OPENAI_TEMPERATURE = temperature ? Float(temperature) : nil
TAVILY_API_KEY = setting('TAVILY_API_KEY', default: nil) # nil = no web_search tool

# --- Developer settings ---
# How much the model thinks before replying: none, low, medium, high, xhigh
# (The bot uses OpenAI's Responses API, which allows tools + thinking together.)
OPENAI_REASONING_EFFORT = saved_setting('OPENAI_REASONING_EFFORT', 'low')
# If thinking uses up the whole budget and the reply is empty, retry once with this instead
OPENAI_FALLBACK_REASONING_EFFORT = saved_setting('OPENAI_FALLBACK_REASONING_EFFORT', 'none')
# Max tokens per reply, thinking + reply together. Only what is used is billed.
OPENAI_MAX_OUTPUT_TOKENS = saved_setting('OPENAI_MAX_OUTPUT_TOKENS', 4000)

# AI chat memory per channel: keep at most this many messages, and at most about this many tokens.
# Whichever limit is reached first wins. Oldest whole turns are removed first.
# !neuronactivate also loads this many recent channel messages as the starting memory.
MAX_HISTORY_MESSAGES = saved_setting('MAX_HISTORY_MESSAGES', 45)
MAX_HISTORY_TOKENS = saved_setting('MAX_HISTORY_TOKENS', 5_000)

# --- Long-term memory (see docs/superpowers/specs/2026-11-04-long-term-memory-design.md) ---
# Where memory files live: memory/<server_id>/... (ignored by git). Tests point this at a temp folder.
MEMORY_DIR = ENV['CAKE_TEST_MEMORY_DIR'] || File.join(__dir__, 'memory')

# Compaction: when the history goes over MAX_HISTORY_MESSAGES / MAX_HISTORY_TOKENS (the "high mark"),
# the oldest turns are summarized in one request and the history is cut down to this "low mark".
COMPACT_TARGET_MESSAGES = saved_setting('COMPACT_TARGET_MESSAGES', 20)
COMPACT_TARGET_TOKENS = saved_setting('COMPACT_TARGET_TOKENS', 2_500)
COMPACTION_REASONING_EFFORT = saved_setting('COMPACTION_REASONING_EFFORT', 'low')

# Safety net: if compaction keeps failing (OpenAI down), the history may grow up to here,
# then the oldest turns are cut without a summary, so costs can't run away. About 1.5x the high mark.
HARD_MAX_HISTORY_MESSAGES = saved_setting('HARD_MAX_HISTORY_MESSAGES', 68)
HARD_MAX_HISTORY_TOKENS = saved_setting('HARD_MAX_HISTORY_TOKENS', 7_500)

# Temporary guard until real size limits are designed: memory text put into the prompt is cut here
MEMORY_PROMPT_MAX_CHARS = 8_000
# Longest fact remember_about_me accepts
REMEMBER_FACT_MAX_CHARS = 500
# After a reply, the sender's facts are checked for overlaps if they have at least this many (see memory_tidy.rb)
MEMORY_TIDY_MIN_FACTS = 2
MEMORY_TIDY_MAX_NEW_FACTS = 5 # one change can't turn into more facts than this
MEMORY_CHECK_RETRY_SECONDS = 3600 # after a failed conflict check, wait this long before trying that person again
OPEN_QUESTION_MAX_MESSAGES = 3 # the AI is reminded of a memory question for this many messages from that person
ASKED_QUESTIONS_KEPT = 5 # tidying is told this many of a person's past questions, so it doesn't repeat them

# Tools (web search, reading pages). One "round" = the AI asks for tools, we run them, send results back.
# After this many rounds the AI must answer, so it can never loop forever.
MAX_TOOL_ROUNDS = saved_setting('MAX_TOOL_ROUNDS', 7)
SEARCH_MAX_RESULTS = saved_setting('SEARCH_MAX_RESULTS', 5) # results per web_search
WEBPAGE_MAX_CHARS = saved_setting('WEBPAGE_MAX_CHARS', 8_000) # read_webpage gives the AI at most this much text (about 2,000 tokens)

# look_at_image: pictures are scaled so the longest side is at most this (about 1,200 tokens per picture)
IMAGE_MAX_SIDE = 1024
IMAGE_MAX_BYTES = 10_000_000 # bigger downloads are refused
IMAGE_MAX_PER_REPLY = saved_setting('IMAGE_MAX_PER_REPLY', 3) # keeps the cost of one reply small

# read_text_file: a file is sent to the AI for one reply only, so long files cost tokens each time they are read
TEXT_FILE_MAX_BYTES = 1_000_000 # bigger downloads are refused
TEXT_FILE_MAX_CHARS = 30_000 # the AI reads at most this much of a file (about 10,000 tokens)
TEXT_FILE_MAX_PER_REPLY = saved_setting('TEXT_FILE_MAX_PER_REPLY', 2) # keeps the cost of one reply small

# Moderation (moderation.rb): free OpenAI check, run on text before it is saved to memory
MODERATION_MODEL = 'omni-moderation-latest'

# search_memory (memory_search.rb): finds memories by meaning using embeddings
EMBEDDING_MODEL = 'text-embedding-3-small' # cheapest embedding model; changing it re-embeds everything once
EMBEDDING_MAX_CHARS = 8_000 # one note is cut here before embedding (about 2,000 tokens)
MEMORY_SEARCH_RESULTS = saved_setting('MEMORY_SEARCH_RESULTS', 5) # how many matches the AI gets back
MEMORY_SEARCH_PREVIEW_CHARS = 300 # how much of each match the AI sees (it can open the note with read_memory)

# search_channel_history (channel_search.rb): read older messages of the current channel as evidence
CHANNEL_SEARCH_MAX_MESSAGES = saved_setting('CHANNEL_SEARCH_MAX_MESSAGES', 500) # how far back one search reads (Discord gives 100 per request, so 5 requests)
CHANNEL_SEARCH_RESULTS = saved_setting('CHANNEL_SEARCH_RESULTS', 10) # how many messages the AI gets back
CHANNEL_SEARCH_MESSAGE_CHARS = 300 # each found message is cut here
CHANNEL_SEARCH_EMBED_CHARS = 500 # each message is cut here before embedding (search by meaning)
CHANNEL_SEARCHES_PER_REPLY = saved_setting('CHANNEL_SEARCHES_PER_REPLY', 3) # enough to try another date once or twice, but keeps one reply quick
CHANNEL_EMBEDDING_CACHE_MAX = 20_000 # message vectors kept in RAM; cleared when it gets bigger

# !buildmemory (build_memory.rb): admins build personality notes from old messages in every channel
BUILD_MEMORY_MESSAGES_PER_CHANNEL = saved_setting('BUILD_MEMORY_MESSAGES_PER_CHANNEL', 2000) # how far back it reads in each channel (20 Discord requests per channel)
BUILD_MEMORY_MIN_MESSAGES = saved_setting('BUILD_MEMORY_MIN_MESSAGES', 5) # people with fewer messages than this are skipped (not enough to go on)
BUILD_MEMORY_MAX_PEOPLE = saved_setting('BUILD_MEMORY_MAX_PEOPLE', 50) # the most active people first; one OpenAI request per person
BUILD_MEMORY_MAX_CHARS_PER_PERSON = saved_setting('BUILD_MEMORY_MAX_CHARS_PER_PERSON', 12_000) # their newest messages, up to this much text (about 3,000 tokens)
BUILD_MEMORY_REASONING_EFFORT = saved_setting('BUILD_MEMORY_REASONING_EFFORT', 'low')

# !clear (clear_messages.rb): admins delete recent messages, optionally only one person's
CLEAR_MAX_MESSAGES = saved_setting('CLEAR_MAX_MESSAGES', 100) # Discord deletes at most 100 messages in one go
CLEAR_SCAN_MESSAGES = saved_setting('CLEAR_SCAN_MESSAGES', 500) # with a person: how far back to look for their messages
CLEAR_REPORT_SECONDS = saved_setting('CLEAR_REPORT_SECONDS', 5) # the "Deleted N messages" note disappears after this long

# Shared recent memory (recent_activity.rb): what happened around Cake lately in every channel, in RAM only.
# It goes into every reply's prompt as "Recently, in other channels", so keep it short.
RECENT_ACTIVITY_HOURS = saved_setting('RECENT_ACTIVITY_HOURS', 2) # older lines are dropped
RECENT_ACTIVITY_MAX_LINES = saved_setting('RECENT_ACTIVITY_MAX_LINES', 20) # in the whole server
RECENT_ACTIVITY_MAX_PER_CHANNEL = saved_setting('RECENT_ACTIVITY_MAX_PER_CHANNEL', 8) # one busy channel can't push the others out
RECENT_ACTIVITY_ANSWER_CHARS = saved_setting('RECENT_ACTIVITY_ANSWER_CHARS', 200) # Cake's answer is cut here in a line
RECENT_ACTIVITY_QUESTION_CHARS = 200 # the question is cut here

# A reply shows who it answers and this much of that message's text
REPLY_QUOTE_MAX_CHARS = 100
