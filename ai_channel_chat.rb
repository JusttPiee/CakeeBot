# Answering a message in an AI channel (!neuronactivate), where Cake replies to everything.
# The caller (cakee.rb) holds the channel lock, so one channel's messages are handled in order.
#
# 1. Save the message in the channel's history
# 2. Ask the AI, with the server's memory and this channel's summary
# 3. Reply (the "Thinking..." line is edited into the answer), and save the reply
# 4. If the history is now too big, compact it (summarize the oldest turns into the memory files)
require_relative './chat_history'
require_relative './ai_chat'
require_relative './compaction'
require_relative './message_logger'
require_relative './image_attachments'
require_relative './memory_tidy'
require_relative './discord_history'
require_relative './recent_activity_events' # write each answer into the shared recent memory
require_relative './command_context' # what the command tools (help, music, clear) need
require_relative './thinking_reply' # the "Thinking..." line that becomes the answer

# music: the MusicController (cakee.rb), for the music tool. nil = no music (tests).
def answer_ai_channel_message(event, client, history, music = nil)
  add_user_message(history, speaker_label(event.author), event.author.id, text_with_attachment_markers(event.message), Time.now,
                   message_id: event.message.id, images: images_from_message(event.message),
                   text_files: text_files_from_message(event.message))
  add_reply_note(history.last, event.message)
  # Safety net: normally compaction keeps the history small. If it keeps failing, cut the old way here.
  trim_history(history, HARD_MAX_HISTORY_MESSAGES, HARD_MAX_HISTORY_TOKENS)

  bot_name = event.server.bot.display_name
  context = ai_channel_context(event, music)
  # "<emoji> Thinking..." while waiting for OpenAI, then edited into the answer (thinking_reply.rb)
  answer, sent = with_thinking(event) { |thinking| ask_and_deliver(event, thinking, client, history, bot_name, context) }
  if answer.nil?
    remove_last_message(history) # Don't keep a question that never got an answer
    return
  end

  log_bot_reply(event, answer)
  save_answer(event, history, answer, context[:command_labels], sent&.id)
  tidy_and_ask(event, client, history)
  compact_history(client, history, event.server.id, event.channel.id, bot_name) if needs_compaction?(history)
end

# Saves Cake's answer in the history. A command turn (labels not empty) is stored with its labels
# and command: true, and is not written to the shared recent memory (a command is not a conversation).
def save_answer(event, history, answer, labels, message_id)
  if labels.empty?
    record_recent_answer(event, answer)
    add_assistant_message(history, answer, message_id: message_id)
  else
    add_assistant_message(history, mark_command_turn(history, labels, answer), message_id: message_id, command: true)
  end
end

# Facts from Discord for memory and tools. The AI never chooses these.
# channel: this channel, so search_channel_history can read back through it (see discord_history.rb).
# The command tools' facts come from command_context (command_context.rb).
def ai_channel_context(event, music = nil)
  { server_id: event.server.id, channel_id: event.channel.id, channel: ReadingChannel.new(event.channel, event.bot),
    requester_id: event.author.id, requester_name: event.author.display_name }.merge(command_context(event, music))
end
