# Chat memory for AI mode.
# Each channel has its own history (a list of messages), kept in RAM only, so it resets when the bot restarts.
# The history is trimmed so every OpenAI request stays small and cheap.

MAX_HISTORY_MESSAGES = 20    # keep at most this many messages per channel
MAX_HISTORY_TOKENS   = 5_000 # ...and at most about this many tokens

# A hash of channel_id => history. A new channel gets an empty history automatically.
def create_history_store
  Hash.new { |store, channel_id| store[channel_id] = [] }
end

# Save the user's message, with their nickname and user ID in front so the AI knows who is speaking.
# Example: "Bach (123456789): hello"
def add_user_message(history, name, user_id, text)
  history << { role: "user", content: "#{name} (#{user_id}): #{text}" }
end

def add_assistant_message(history, text)
  history << { role: "assistant", content: text }
end

# Used when the AI request fails, so the unanswered user message does not stay in memory
def remove_last_message(history)
  history.pop
end

# Rough token count: about 4 characters per token (good enough for a budget, no extra gem needed)
def estimate_tokens(history)
  total_chars = history.sum { |message| message[:content].to_s.length }
  total_chars / 4
end

def too_big?(history)
  history.length > MAX_HISTORY_MESSAGES || estimate_tokens(history) > MAX_HISTORY_TOKENS
end

# A "turn" = one user message + everything that answers it (assistant reply, and later tool calls)
def turn_count(history)
  history.count { |message| message[:role] == "user" }
end

# Remove the oldest user message, then everything after it until the next user message
def remove_oldest_turn(history)
  history.shift
  history.shift while history.any? && history.first[:role] != "user"
end

# Remove whole turns from the oldest side until the history fits.
# A turn is never cut in half, and the newest turn is always kept.
def trim_history(history)
  while too_big?(history) && turn_count(history) > 1
    remove_oldest_turn(history)
  end
end

# OpenAI expects a list of { role:, content: } hashes
def format_history_for_openai(history)
  history.map { |message| { role: message[:role], content: message[:content] } }
end
