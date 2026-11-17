# Delete / Cancel buttons for "clear messages" asked through the AI (the clear_messages tool).
# Cake never deletes on the AI's say-so alone: it posts a question with two buttons, and only the person
# who asked (and only while they are still an admin) can confirm.
#
# Everything the button needs is in its custom id, so it still works after a restart:
#   aiclear:yes:<requester_id>:<amount>:<user_id or 0>:<request_message_id>
#   aiclear:no:<requester_id>
require 'set'
require 'discordrb' # the buttons (Discordrb::Webhooks::View)
require_relative './config'
require_relative './clear_messages'

CLEAR_CONFIRM_PREFIX = "aiclear"

# Confirm messages whose Delete button was already used. A second press (a double click) does nothing.
CLEAR_CONFIRM_HANDLED = Set.new

# --- the button ids ---

# [id of the Delete button, id of the Cancel button]. user_id nil (everyone) is written as 0.
def clear_confirm_ids(requester_id, amount, user_id, request_message_id)
  yes_id = [CLEAR_CONFIRM_PREFIX, "yes", requester_id, amount, user_id || 0, request_message_id].join(":")
  [yes_id, "#{CLEAR_CONFIRM_PREFIX}:no:#{requester_id}"]
end

# The other way round. Numbers are Integers, user_id is a String (or nil), as messages_to_clear compares strings.
# Not one of our ids => nil
def parse_clear_confirm_id(custom_id)
  parts = custom_id.to_s.split(":")
  return nil unless parts.first == CLEAR_CONFIRM_PREFIX

  if parts[1] == "yes" && parts.length == 6
    parse_yes_parts(parts)
  elsif parts[1] == "no" && parts.length == 3
    { answer: :no, requester_id: parts[2].to_i }
  end
end

def parse_yes_parts(parts)
  user_id = parts[4] == "0" ? nil : parts[4]
  { answer: :yes, requester_id: parts[2].to_i, amount: parts[3].to_i, user_id: user_id,
    request_message_id: parts[5].to_i }
end

# --- asking ---

# Posts the question with its two buttons in the channel.
def post_clear_confirm(channel, requester_id, amount, user_id, request_message_id)
  yes_id, no_id = clear_confirm_ids(requester_id, amount, user_id, request_message_id)
  channel.send_message(clear_confirm_text(requester_id, amount, user_id), false, nil, nil, nil, nil,
                       clear_confirm_view(yes_id, no_id))
end

def clear_confirm_text(requester_id, amount, user_id)
  whose = user_id ? " from <@#{user_id}>" : ""
  "🧹 Delete the newest #{amount} messages#{whose} in this channel? Only <@#{requester_id}> can confirm."
end

def clear_confirm_view(yes_id, no_id)
  Discordrb::Webhooks::View.new do |view|
    view.row do |row|
      row.button(style: :danger, label: "Delete", custom_id: yes_id)
      row.button(style: :secondary, label: "Cancel", custom_id: no_id)
    end
  end
end

# --- a button press ---

# reader and now are only given by tests. Returns nil.
def clear_confirm_pressed(event, reader = ReadingChannel, now = Time.now)
  answer = parse_clear_confirm_id(event.custom_id)
  return nil if answer.nil?

  problem = clear_confirm_problem(event, answer, now)
  return clear_confirm_refuse(event, problem) if problem

  if answer[:answer] == :no
    event.update_message(content: "Cancelled.", components: [])
  else
    clear_confirm_run(event, answer, reader)
  end
  nil
rescue StandardError => e
  log "🧹 clear confirm failed (#{e.class}): #{e.message}"
  clear_confirm_show_error(event, e)
  nil
end

# After the buttons are gone, the requester would see nothing: put the error on the confirm message.
# Never raises (it runs inside a rescue).
def clear_confirm_show_error(event, error)
  return unless CLEAR_CONFIRM_HANDLED.include?(event.message&.id)

  event.edit_response(content: clear_error_text(error), components: [])
rescue StandardError => e
  log "🧹 could not show the clear error (#{e.class})"
end

# Why this press does nothing: { text:, expired: true or false } or nil when it may go on.
def clear_confirm_problem(event, answer, now)
  if event.user.id != answer[:requester_id]
    { text: "Only <@#{answer[:requester_id]}> can confirm this." }
  elsif now - event.message.creation_time > CLEAR_CONFIRM_SECONDS
    { text: "⌛ This request expired, ask again.", expired: true }
  elsif answer[:answer] == :yes && !event.user.permission?(:administrator)
    { text: "⛔ Only admins can delete messages." }
  end
end

# An expired question is edited so the buttons go away. Other problems are shown only to the person who pressed.
def clear_confirm_refuse(event, problem)
  if problem[:expired]
    event.update_message(content: problem[:text], components: [])
  else
    event.respond(content: problem[:text], ephemeral: true)
  end
  nil
end

# Deletes the messages, then the conversation that asked for it, then says what happened.
def clear_confirm_run(event, answer, reader)
  target = { user_id: answer[:user_id], amount: answer[:amount] }
  return unless CLEAR_CONFIRM_HANDLED.add?(event.message.id) # a second press: already being done

  # Answer Discord within 3 seconds and remove the buttons at once, so nobody can press Delete again
  event.update_message(content: "🧹 Deleting…", components: [])
  conversation = clear_conversation_ids(event, answer[:request_message_id], reader)
  deleted, too_old = clear_messages_before(event.channel, event.bot, answer[:request_message_id], target, reader, conversation)
  log "🧹 AI clear by #{event.user.display_name} (#{event.user.id}) in ##{event.channel.name}: " \
      "deleted #{deleted} #{target[:user_id] ? "from user #{target[:user_id]}" : 'from everyone'}, skipped #{too_old} too old"
  send_temporary_note(event.channel, clear_report_text(deleted, too_old, target), CLEAR_REPORT_SECONDS)
end

# The messages of the conversation that go too (not counted): the request, the confirm message, and
# Cake's text reply. The reply starts as the "Thinking..." message (sent before the confirm message, as a
# reply to the request) and is edited into the answer later; an edit keeps its author and its reply
# reference, so it is found by reading what came after the request. Nothing else is deleted: other people's messages
# (and Cake's messages that answer something else) stay.
def clear_conversation_ids(event, request_id, reader)
  after = reader.new(event.channel, event.bot).raw_history(DISCORD_PAGE_SIZE, nil, request_id)
  cake_id = event.bot.profile.id
  replies = after.select { |message| cake_reply_to?(message, cake_id, request_id) }
  [request_id, event.message.id] + replies.map { |message| raw_id(message) }
end

# True for a message Cake wrote as a reply to the request (the reply may be split in several messages)
def cake_reply_to?(message, cake_id, request_id)
  message.dig("author", "id").to_i == cake_id && message.dig("message_reference", "message_id").to_i == request_id
end
