# Chat memory for AI mode.
# Each channel has its own history (a list of messages), kept in RAM only, so it resets when the bot restarts.
# The history is trimmed so every OpenAI request stays small and cheap.

# The limits (MAX_HISTORY_MESSAGES, MAX_HISTORY_TOKENS) are in config.rb
require_relative './config'
require_relative './time_ago'

# A hash of channel_id => history. A new channel gets an empty history automatically.
def create_history_store
  Hash.new { |store, channel_id| store[channel_id] = [] }
end

# Save the user's message, with their nickname and user ID in front so the AI knows who is speaking.
# Example: "Bach (123456789): hello"
# `time` is when it was sent; the "[5 minutes ago]" marker is added later, when sending to OpenAI,
# because "how long ago" keeps changing.
def add_user_message(history, name, user_id, text, time = Time.now)
  history << { role: "user", content: "#{name} (#{user_id}): #{text}", time: time }
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

# OpenAI expects a list of { role:, content: } hashes.
# User messages get a time marker in front: "[2 hours ago] Bach (123): hello"
def format_history_for_openai(history, now = Time.now)
  history.map { |message| { role: message[:role], content: content_with_time(message, now) } }
end

def content_with_time(message, now)
  return message[:content] if message[:role] != "user" || message[:time].nil?

  "[#{time_ago(message[:time], now)}] #{message[:content]}"
end
