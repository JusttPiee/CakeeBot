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

# Tools (web search, reading pages). One "round" = the AI asks for tools, we run them, send results back.
# After this many rounds the AI must answer, so it can never loop forever.
MAX_TOOL_ROUNDS = 3
SEARCH_MAX_RESULTS = 5 # results per web_search
WEBPAGE_MAX_CHARS = 8_000 # read_webpage gives the AI at most this much text (about 2,000 tokens)
