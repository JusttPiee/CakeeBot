# Chat memory for AI mode.
# Each channel has its own history (a list of messages), kept in RAM only, so it resets when the bot restarts.
# The history is trimmed so every OpenAI request stays small and cheap.

# The limits (MAX_HISTORY_MESSAGES, MAX_HISTORY_TOKENS) are in config.rb
require_relative './config'

# A hash of channel_id => history. A new channel gets an empty history automatically.
def create_history_store
  Hash.new { |store, channel_id| store[channel_id] = [] }
end

# Save the user's message, with their nickname and user ID in front so the AI knows who is speaking.
# Example: "Bach (123456789): hello"
# `time` is when it was sent; the "[2026-11-04 14:02]" marker is added when sending to OpenAI.
# user_id, name and message_id (the Discord message) are kept for compaction and long-term memory.
def add_user_message(history, name, user_id, text, time = Time.now, message_id: nil)
  history << { role: "user", content: "#{name} (#{user_id}): #{text}", time: time,
               user_id: user_id.to_s, name: name, message_id: message_id }
end

# message_id: the Discord message Cake sent (the last one, if the reply was split)
def add_assistant_message(history, text, message_id: nil)
  history << { role: "assistant", content: text, message_id: message_id }
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

def too_big?(history, max_messages = MAX_HISTORY_MESSAGES, max_tokens = MAX_HISTORY_TOKENS)
  history.length > max_messages || estimate_tokens(history) > max_tokens
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
def trim_history(history, max_messages = MAX_HISTORY_MESSAGES, max_tokens = MAX_HISTORY_TOKENS)
  while too_big?(history, max_messages, max_tokens) && turn_count(history) > 1
    remove_oldest_turn(history)
  end
end

# The Discord id of the newest message that has one (nil if none do)
def last_message_id(messages)
  messages.map { |message| message[:message_id] }.compact.last
end

# OpenAI expects a list of { role:, content: } hashes.
# User messages get a fixed timestamp in front: "[2026-11-04 14:02] Bach (123): hello"
# The timestamp never changes, so the same history is sent as the same text every time.
# That lets OpenAI's prompt cache reuse it (cached input is billed much cheaper).
def format_history_for_openai(history)
  history.map { |message| { role: message[:role], content: content_with_time(message) } }
end

def content_with_time(message)
  return message[:content] if message[:role] != "user" || message[:time].nil?

  "[#{format_timestamp(message[:time])}] #{message[:content]}"
end

# Bot's local time, to the minute. getlocal makes Discord's UTC times match Time.now.
def format_timestamp(time)
  time.getlocal.strftime('%Y-%m-%d %H:%M')
end
