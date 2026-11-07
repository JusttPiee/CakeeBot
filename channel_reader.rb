# When AI mode is turned on, read the channel's recent messages so the AI knows what people were talking about.
# This runs on !neuronactivate, and again when the bot starts (so a restart doesn't make it forget).
# After that, the history just grows and trims as usual.
require_relative './chat_history'
require_relative './channel_lock'
require_relative './channel_summary'
require_relative './image_attachments'

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
    histories[channel.id] = load_ai_channel_history(channel, bot.profile.id)
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

# History for an AI channel (on startup and on !neuronactivate):
# only the messages that are not already in the channel summary, kept up to the hard ceiling,
# so compaction can still summarize them on the next reply instead of them being cut.
def load_ai_channel_history(channel, bot_id)
  summary = read_channel_summary(channel.server.id, channel.id)
  load_channel_history(channel, bot_id, after_id: summary[:last_message_id],
                                        max_messages: HARD_MAX_HISTORY_MESSAGES, max_tokens: HARD_MAX_HISTORY_TOKENS)
end

# Fetch the last MAX_HISTORY_MESSAGES messages from Discord and turn them into chat history.
# after_id: skip messages up to this Discord id (they are already in the channel summary).
# max_messages / max_tokens: how much to keep (AI channels keep more, compaction shrinks it later).
# If Discord refuses (e.g. no "Read Message History" permission), log it and start with an empty history.
def load_channel_history(channel, bot_id, after_id: nil, max_messages: MAX_HISTORY_MESSAGES, max_tokens: MAX_HISTORY_TOKENS)
  messages = channel.history(MAX_HISTORY_MESSAGES)
  messages = messages_after(messages, after_id)
  build_history_from_messages(messages, bot_id, max_messages: max_messages, max_tokens: max_tokens)
rescue StandardError => e
  log "⚠️ Could not read recent messages in ##{channel.name} (#{e.class}). Starting with empty memory."
  []
end

# Only the messages newer than after_id (Discord ids grow over time). Messages without an id are kept.
def messages_after(messages, after_id)
  return messages if after_id.nil?

  messages.select { |message| message.id.nil? || message.id > after_id }
end

# messages: Discord messages, newest first (the order Discord returns them in)
def build_history_from_messages(messages, bot_id, max_messages: MAX_HISTORY_MESSAGES, max_tokens: MAX_HISTORY_TOKENS)
  history = []
  messages.reverse.each do |message| # oldest first, like a normal conversation
    from_bot = message.author.id == bot_id
    text = from_bot ? message.content.to_s.strip : text_with_attachment_markers(message)
    next if text.empty? # stickers or embeds only: nothing to give the AI

    if from_bot
      add_assistant_message(history, text, message_id: message.id)
    else
      add_user_message(history, message.author.display_name, message.author.id, text, message.creation_time,
                       message_id: message.id, images: images_from_message(message),
                       text_files: text_files_from_message(message))
      add_reply_note(history.last, message)
    end
  end
  trim_history(history, max_messages, max_tokens) # the size limits still apply
  history
end
