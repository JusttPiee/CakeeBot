# !clear (admins only): delete recent messages in this channel. Moderation, no AI.
#   !clear 50        deletes the 50 newest messages
#   !clear @Pie 50   deletes Pie's 50 newest messages (looks back through the last CLEAR_SCAN_MESSAGES)
# The !clear message itself is deleted too, and is not counted.
#
# Discord rules:
#   - at most 100 messages at once (CLEAR_MAX_MESSAGES)
#   - messages older than 14 days can't be deleted in one go, only one by one, which is very slow.
#     They are skipped, and the report says how many.
#   - the bot needs the "Manage Messages" permission in the channel.
#
# Messages are read as raw JSON (discord_history.rb), so people who left the server don't slow it down.
require_relative './config'
require_relative './discord_history'
require_relative './temporary_note'

CLEAR_USAGE = "Usage: `!clear <amount>` or `!clear @user <amount>`, amount 1 to #{CLEAR_MAX_MESSAGES}."
DISCORD_BULK_DELETE_MAX_AGE = 14 * 24 * 3600 # 14 days, in seconds
BULK_DELETE_SAFETY_SECONDS = 60 # a message just under 14 days old could pass the limit before Discord gets the request

# --- reading the command ---

# ["50"] => { user_id: nil, amount: 50 }, ["<@456>", "50"] => { user_id: "456", amount: 50 }.
# Anything else => nil
def parse_clear_arguments(args)
  return nil unless args.length.between?(1, 2)

  user_text = args.length == 2 ? args[0] : nil
  amount = Integer(args.last, exception: false)
  return nil if amount.nil? || !amount.between?(1, CLEAR_MAX_MESSAGES)

  user_id = user_text ? user_id_from_mention(user_text) : nil
  return nil if user_text && user_id.nil?

  { user_id: user_id, amount: amount }
end

# "<@456>", "<@!456>" or just "456" => "456". Anything else => nil
def user_id_from_mention(text)
  match = text.match(/\A<@!?(\d+)>\z/) || text.match(/\A(\d+)\z/)
  match && match[1]
end

# --- choosing the messages ---

# How many messages to read: just enough without a person, more with one (their messages are spread out).
# +1 because the newest message is the !clear command itself.
def clear_read_amount(target)
  target[:user_id] ? CLEAR_SCAN_MESSAGES : target[:amount] + 1
end

# raw_messages: newest first. Returns the ones to delete, newest first, without the command itself.
def messages_to_clear(raw_messages, command_id, target)
  candidates = raw_messages.reject { |message| raw_id(message) == command_id }
  if target[:user_id]
    candidates = candidates.select { |message| message.dig("author", "id").to_s == target[:user_id] }
  end
  candidates.first(target[:amount])
end

# [ids that can be deleted, how many are too old]
def split_by_age(raw_messages, now = Time.now)
  oldest_allowed = now - DISCORD_BULK_DELETE_MAX_AGE + BULK_DELETE_SAFETY_SECONDS
  recent = raw_messages.select { |message| Time.parse(message["timestamp"].to_s) > oldest_allowed }
  [recent.map { |message| raw_id(message) }, raw_messages.length - recent.length]
end

# --- deleting ---

# Discord's bulk delete needs 2 to 100 messages, so a single message is deleted on its own
def delete_message_ids(channel, ids)
  return if ids.empty?

  if ids.length == 1
    channel.delete_message(ids.first)
  else
    channel.delete_messages(ids)
  end
end

def clear_report_text(deleted, too_old, target)
  whose = target[:user_id] ? " from <@#{target[:user_id]}>" : ""
  text = "🧹 Deleted #{deleted} message#{deleted == 1 ? '' : 's'}#{whose}."
  text += " Skipped #{too_old} older than 14 days (Discord doesn't allow deleting those in bulk)." if too_old.positive?
  text
end

# --- the Discord command ---

# reader is only given by tests; normally messages are read with a ReadingChannel (discord_history.rb).
def clear_command(event, args, reader = ReadingChannel)
  problem = clear_problem(event)
  return event.respond(problem) if problem

  target = parse_clear_arguments(args)
  return event.respond(CLEAR_USAGE) if target.nil?

  run_clear(event, target, reader)
rescue StandardError => e
  log "⚠️ !clear failed in #{event.channel&.name} (#{e.class})"
  event.respond(clear_error_text(e))
end

# Why !clear can't run (text for Discord), or nil if it can.
# The admin check is in code: nothing anyone writes can give this permission.
def clear_problem(event)
  return "❗ `!clear` only works in a server." if event.server.nil?
  return "⛔ Only admins can use `!clear`." unless event.user.permission?(:administrator)

  nil
end

def run_clear(event, target, reader)
  raw_messages = fetch_older_messages(reader.new(event.channel, event.bot), clear_read_amount(target))
  ids, too_old = split_by_age(messages_to_clear(raw_messages, event.message.id, target))
  delete_message_ids(event.channel, ids + [event.message.id]) # the command goes too
  log_clear(event, target, ids.length, too_old)
  send_temporary_note(event.channel, clear_report_text(ids.length, too_old, target), CLEAR_REPORT_SECONDS)
end

def log_clear(event, target, deleted, too_old)
  whose = target[:user_id] ? "from user #{target[:user_id]}" : "from everyone"
  log "🧹 !clear by #{event.author.display_name} (#{event.author.id}) in ##{event.channel.name}: " \
      "deleted #{deleted} #{whose}, skipped #{too_old} too old"
end

# Missing "Manage Messages" is the usual reason, so say that clearly
def clear_error_text(error)
  no_permission = defined?(Discordrb::Errors::NoPermission) && error.is_a?(Discordrb::Errors::NoPermission)
  if no_permission
    "⛔ I need the **Manage Messages** permission in this channel to delete messages."
  else
    "❗ Could not delete the messages, please try again later."
  end
end
