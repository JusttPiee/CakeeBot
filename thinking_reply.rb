# The "<emoji> Thinking..." line in AI channels and mentions.
# Cake sends it as a reply while it waits for the AI, then edits it into the answer
# (never deletes it: another bot on the server tracks deleted messages).
# The answer's :name: emojis are converted to Discord's form only here, so the history keeps :name:.
require_relative './config'
require_relative './message_splitter'
require_relative './message_edit' # Message#edit_without_ping
require_relative './emoji_library'
require_relative './ai_chat' # ask_ai
require_relative './command_context' # done_if_command_ran

AI_UNAVAILABLE_MESSAGE = "⚠️ My AI brain is unavailable right now. Please try again later."

# "<:thinking:123> Thinking...", or "🤔 Thinking..." when the bot has no emoji with that name
def thinking_text(library = EMOJIS)
  "#{library.discord_form(THINKING_EMOJI) || '🤔'} Thinking..."
end

# Replies with the Thinking line, without pinging. Returns the message, or nil if Discord refused it.
def send_thinking(event, library = EMOJIS)
  event.message.reply!(thinking_text(library), mention_user: false)
rescue StandardError => e
  log "😀 could not send the Thinking line (#{e.class}): #{e.message}"
  nil
end

# Sends the Thinking line, then runs the block with it, and gives back the block's result.
# If the block raises, the Thinking line is turned into the unavailable text (it must never stay
# "Thinking..." forever), and the error goes on, so discordrb still logs it.
def with_thinking(event)
  thinking = send_thinking(event)
  yield thinking
rescue StandardError
  show_unavailable(event, thinking)
  raise
end

# Best effort: an error here is only logged, so the original error is the one that goes on
def show_unavailable(event, thinking)
  deliver_answer(event, thinking, AI_UNAVAILABLE_MESSAGE)
rescue StandardError => e
  log "😀 could not replace the Thinking line after an error (#{e.class}): #{e.message}"
end

# Asks the AI and sends the answer into the Thinking line.
# Returns [answer, last message sent]. With no answer, the unavailable text is sent and [nil, nil] returned.
def ask_and_deliver(event, thinking, client, history, bot_name, context)
  answer = done_if_command_ran(ask_ai(client, history, bot_name, context), context[:command_labels])
  if answer.nil? || answer.strip.empty?
    deliver_answer(event, thinking, AI_UNAVAILABLE_MESSAGE)
    return [nil, nil]
  end

  [answer, deliver_answer(event, thinking, answer)]
end

# The AI's text, ready for Discord: :name: emojis converted, their uses counted, split into chunks.
# The split comes after converting, because Discord's limit is about the text it receives.
def emoji_chunks(text, library = EMOJIS)
  converted = library.to_discord(text)
  count_emoji_uses(library, text)
  split_message(converted)
end

# Counting is an extra: if it fails (a broken notes file, for example), the answer still goes out
def count_emoji_uses(library, text)
  library.record_uses(text)
rescue StandardError => e
  log "😀 could not count emoji uses (#{e.class}): #{e.message}"
end

# Sends the AI's text: the first chunk replaces the Thinking line, the rest go as new replies.
# Returns the last message sent (its id goes into the history).
def deliver_answer(event, thinking, text, library = EMOJIS)
  chunks = emoji_chunks(text, library)
  sent = edit_or_reply(event, thinking, chunks.first)
  chunks.drop(1).each { |chunk| sent = event.message.reply!(chunk, mention_user: false) }
  sent
end

# Edits the Thinking line into this chunk. With no Thinking line, or if the edit fails
# (the message was deleted, for example), the chunk is sent as a normal reply.
def edit_or_reply(event, thinking, chunk)
  return nil if chunk.nil?

  if thinking
    begin
      thinking.edit_without_ping(chunk) # a plain edit would ping the person again (message_edit.rb)
      return thinking
    rescue StandardError => e
      log "😀 could not edit the Thinking line (#{e.class}), replying instead"
    end
  end
  event.message.reply!(chunk, mention_user: false)
end
