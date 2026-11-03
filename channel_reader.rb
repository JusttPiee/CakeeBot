# When AI mode is turned on, read the channel's recent messages so the AI knows what people were talking about.
# This runs on !neuronactivate, and again when the bot starts (so a restart doesn't make it forget).
# After that, the history just grows and trims as usual.
require_relative './chat_history'
require_relative './channel_lock'

# On startup: for every channel where AI mode was on (saved in ai_config.txt), load its
# recent messages again, so the AI remembers the conversations from before the restart.
def restore_ai_memory(bot, histories, channel_ids)
  if channel_ids.empty?
    log "🧠 AI mode is off (no channel activated with !neuronactivate)"
    return
  end

  channel_ids.each { |channel_id| restore_channel_memory(bot, histories, channel_id) }
end

def restore_channel_memory(bot, histories, channel_id)
  channel = find_channel(bot, channel_id)
  return if channel.nil?

  with_channel_lock(channel.id) do
    histories[channel.id] = load_channel_history(channel, bot.profile.id)
  end
  log "🧠 AI mode is on in #{channel.server&.name} ##{channel.name}: loaded #{histories[channel.id].length} messages into memory"
end

# The channel from its saved ID, or nil (with a log line) if the bot can't see it anymore
def find_channel(bot, channel_id)
  channel = bot.channel(channel_id)
  log "⚠️ AI channel #{channel_id} not found (deleted, or the bot left that server). Starting with empty memory." if channel.nil?
  channel
rescue StandardError => e
  log "⚠️ Could not open AI channel #{channel_id} (#{e.class}). Starting with empty memory."
  nil
end

# Fetch the last MAX_HISTORY_MESSAGES messages from Discord and turn them into chat history.
# If Discord refuses (e.g. no "Read Message History" permission), log it and start with an empty history.
def load_channel_history(channel, bot_id)
  messages = channel.history(MAX_HISTORY_MESSAGES)
  build_history_from_messages(messages, bot_id)
rescue StandardError => e
  log "⚠️ Could not read recent messages in ##{channel.name} (#{e.class}). Starting with empty memory."
  []
end

# messages: Discord messages, newest first (the order Discord returns them in)
def build_history_from_messages(messages, bot_id)
  history = []
  messages.reverse.each do |message| # oldest first, like a normal conversation
    text = message.content.to_s.strip
    next if text.empty? # pictures, stickers or embeds only: no text to give the AI

    if message.author.id == bot_id
      add_assistant_message(history, text)
    else
      add_user_message(history, message.author.display_name, message.author.id, text, message.creation_time)
    end
  end
  trim_history(history) # the token limit still applies
  history
end
