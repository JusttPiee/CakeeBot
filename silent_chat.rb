# !silent <question>: ask Cake privately. Works in any channel of a server, for everyone.
#   1. the !silent message is deleted right away, so the question only shows for a moment
#   2. Cake reads the channel's recent messages as context, like when it is @mentioned
#   3. the answer is sent to the asker's DMs, never to the channel
#
# Nothing goes into the channel's chat history, and no memory questions are asked in the channel
# (that would show the private conversation). Memory tools still work: they are the asker's own choice.
# If Cake can't DM them (DMs from server members turned off), it says so in the channel for a few seconds.
#
# Discord only has "only you can see this" messages for slash commands, so DMs are used instead.
require_relative './config'
require_relative './channel_reader'
require_relative './channel_lock'
require_relative './chat_history'
require_relative './ai_chat'
require_relative './message_logger'
require_relative './message_splitter'
require_relative './discord_history'
require_relative './mention_chat' # name_bot_mentions
require_relative './temporary_note'

SILENT_COMMAND = /\A!silent\b\s*/i
SILENT_USAGE = "Usage: `!silent <your question>`. I'll answer in your DMs."
SILENT_NOTE = "(asked privately with !silent, your answer goes to their DMs only)"
SILENT_DM_FAILED = "⚠️ I couldn't DM you. Turn on DMs from server members (Privacy Settings) and try again."
SILENT_NOTICE_SECONDS = 10
SILENT_UNAVAILABLE = "⚠️ My AI brain is unavailable right now. Please try again later."

# The question without "!silent" in front. The text is used as typed, so new lines are kept.
def silent_question(content)
  content.to_s.sub(SILENT_COMMAND, "").strip
end

# reader is only given by tests; normally the channel is read with a ReadingChannel (discord_history.rb).
def silent_command(event, client, reader = ReadingChannel)
  return event.respond("❗ `!silent` only works in a server.") if event.server.nil?

  question = silent_question(event.message.content)
  delete_silent_message(event)
  return send_temporary_note(event.channel, SILENT_USAGE, SILENT_NOTICE_SECONDS) if question.empty?

  with_channel_lock(event.channel.id) { answer_silently(event, client, question, reader) }
rescue StandardError => e
  log "⚠️ !silent failed for #{event.author&.display_name} (#{e.class})"
end

# Without "Manage Messages" the question stays in the channel, but the answer is still private
def delete_silent_message(event)
  event.message.delete
rescue StandardError => e
  log "⚠️ !silent could not delete the question in ##{event.channel.name} (#{e.class}), it stays visible"
end

def answer_silently(event, client, question, reader)
  history = silent_history(event, question, reader)
  show_typing_in_dm(event)
  answer = ask_ai(client, history, event.server.bot.display_name, silent_context(event, reader))
  answer = SILENT_UNAVAILABLE if answer.nil? || answer.strip.empty?
  send_silent_answer(event, answer)
end

# The channel's recent messages, then the question as the newest message.
# The !silent message is left out, in case it couldn't be deleted (then it would be there twice).
def silent_history(event, question, reader)
  bot_id = event.bot.profile.id
  history = load_channel_history(reader.new(event.channel, event.bot), bot_id)
  history.reject! { |message| message[:message_id] == event.message.id }
  add_user_message(history, event.author.display_name, event.author.id, "#{question} #{SILENT_NOTE}", Time.now)
  name_bot_mentions(history, bot_id, event.server.bot.display_name)
  history
end

# Like mention_context: the server's memory and tools, no channel summary
def silent_context(event, reader)
  { server_id: event.server.id, channel_id: nil, channel: reader.new(event.channel, event.bot),
    requester_id: event.author.id, requester_name: event.author.display_name }
end

# "Cake is typing..." in their DMs while the AI thinks. Not important enough to fail over.
def show_typing_in_dm(event)
  event.author.pm.start_typing
rescue StandardError
  nil
end

def send_silent_answer(event, answer)
  split_message(answer).each { |chunk| event.author.pm(chunk) }
  log_bot_reply(event, "(DM) #{answer}")
rescue StandardError => e
  log "⚠️ !silent could not DM #{event.author.display_name} (#{e.class})"
  send_temporary_note(event.channel, "<@#{event.author.id}> #{SILENT_DM_FAILED}", SILENT_NOTICE_SECONDS)
end
