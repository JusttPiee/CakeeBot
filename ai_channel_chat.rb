# Answering a message in an AI channel (!neuronactivate), where Cake replies to everything.
# The caller (cakee.rb) holds the channel lock, so one channel's messages are handled in order.
#
# 1. Save the message in the channel's history
# 2. Ask the AI, with the server's memory and this channel's summary
# 3. Reply, and save the reply
# 4. If the history is now too big, compact it (summarize the oldest turns into the memory files)
require_relative './chat_history'
require_relative './ai_chat'
require_relative './compaction'
require_relative './message_logger'
require_relative './image_attachments'
require_relative './memory_tidy'

AI_UNAVAILABLE_MESSAGE = "⚠️ My AI brain is unavailable right now. Please try again later."

def answer_ai_channel_message(event, client, history)
  add_user_message(history, event.author.display_name, event.author.id, text_with_attachment_markers(event.message), Time.now,
                   message_id: event.message.id, images: images_from_message(event.message),
                   text_files: text_files_from_message(event.message))
  add_reply_note(history.last, event.message)
  # Safety net: normally compaction keeps the history small. If it keeps failing, cut the old way here.
  trim_history(history, HARD_MAX_HISTORY_MESSAGES, HARD_MAX_HISTORY_TOKENS)

  event.channel.start_typing # Show "Cake is typing..." while waiting for OpenAI
  bot_name = event.server.bot.display_name
  answer = ask_ai(client, history, bot_name, ai_channel_context(event))

  if answer.nil? || answer.strip.empty?
    remove_last_message(history) # Don't keep a question that never got an answer
    event.message.reply!(AI_UNAVAILABLE_MESSAGE, mention_user: false)
    return
  end

  sent = send_reply(event, answer) # Splits replies over Discord's 2000-character limit
  log_bot_reply(event, answer)
  add_assistant_message(history, answer, message_id: sent&.id)
  tidy_and_ask(event, client, history)
  compact_history(client, history, event.server.id, event.channel.id, bot_name) if needs_compaction?(history)
end

# Facts from Discord for memory and tools. The AI never chooses these.
def ai_channel_context(event)
  { server_id: event.server.id, channel_id: event.channel.id,
    requester_id: event.author.id, requester_name: event.author.display_name }
end
