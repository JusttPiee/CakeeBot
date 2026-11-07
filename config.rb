# All bot settings in one place.
# - Settings read with `setting(...)` can be changed in .env (they are listed in .env.example).
# - Plain constants are developer settings: change them here, in the code.
# Load this AFTER .env has been loaded (cakee.rb does that).

# Read a setting from .env / the environment, or use the default if it is empty
def setting(name, default:)
  value = ENV[name].to_s.strip
  value.empty? ? default : value
end

# --- Can be changed in .env ---
OPENAI_MODEL = setting('OPENAI_MODEL', default: 'gpt-6-luna') # change when OpenAI retires a model
temperature = setting('OPENAI_TEMPERATURE', default: nil) # e.g. "0.7", or nil = model's default
OPENAI_TEMPERATURE = temperature ? Float(temperature) : nil
TAVILY_API_KEY = setting('TAVILY_API_KEY', default: nil) # nil = no web_search tool

# --- Developer settings ---
# How much the model thinks before replying: none, low, medium, high, xhigh
# (The bot uses OpenAI's Responses API, which allows tools + thinking together.)
OPENAI_REASONING_EFFORT = 'low'
# If thinking uses up the whole budget and the reply is empty, retry once with this instead
OPENAI_FALLBACK_REASONING_EFFORT = 'none'
# Max tokens per reply, thinking + reply together. Only what is used is billed.
OPENAI_MAX_OUTPUT_TOKENS = 4000

# AI chat memory per channel: keep at most this many messages, and at most about this many tokens.
# Whichever limit is reached first wins. Oldest whole turns are removed first.
# !neuronactivate also loads this many recent channel messages as the starting memory.
MAX_HISTORY_MESSAGES = 45
MAX_HISTORY_TOKENS = 5_000

# --- Long-term memory (see docs/superpowers/specs/2026-11-04-long-term-memory-design.md) ---
# Where memory files live: memory/<server_id>/... (ignored by git). Tests point this at a temp folder.
MEMORY_DIR = ENV['CAKE_TEST_MEMORY_DIR'] || File.join(__dir__, 'memory')

# Compaction: when the history goes over MAX_HISTORY_MESSAGES / MAX_HISTORY_TOKENS (the "high mark"),
# the oldest turns are summarized in one request and the history is cut down to this "low mark".
COMPACT_TARGET_MESSAGES = 20
COMPACT_TARGET_TOKENS = 2_500
COMPACTION_REASONING_EFFORT = 'low'

# Safety net: if compaction keeps failing (OpenAI down), the history may grow up to here,
# then the oldest turns are cut without a summary, so costs can't run away. About 1.5x the high mark.
HARD_MAX_HISTORY_MESSAGES = 68
HARD_MAX_HISTORY_TOKENS = 7_500

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
MAX_TOOL_ROUNDS = 7
SEARCH_MAX_RESULTS = 5 # results per web_search
WEBPAGE_MAX_CHARS = 8_000 # read_webpage gives the AI at most this much text (about 2,000 tokens)

# look_at_image: pictures are scaled so the longest side is at most this (about 1,200 tokens per picture)
IMAGE_MAX_SIDE = 1024
IMAGE_MAX_BYTES = 10_000_000 # bigger downloads are refused
IMAGE_MAX_PER_REPLY = 3 # keeps the cost of one reply small

# A reply shows who it answers and this much of that message's text
REPLY_QUOTE_MAX_CHARS = 100
