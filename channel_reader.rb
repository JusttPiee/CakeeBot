# When AI mode is turned on, read the channel's recent messages so the AI knows what people were talking about.
# This runs ONCE, on !neuronactivate. After that, the history just grows and trims as usual.
require_relative './chat_history'

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
      add_user_message(history, message.author.display_name, message.author.id, text)
    end
  end
  trim_history(history) # the token limit still applies
  history
end
