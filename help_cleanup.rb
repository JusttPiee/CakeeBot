# Cleans up help messages left over from before a restart.
# A help message deletes itself HELP_CLOSE_AFTER_MINUTES after it was posted (help_command.rb), but that
# timer lives in RAM: a restart (or a help message from before this feature) leaves the message in the chat.
# So on startup, Cake reads the newest HELP_CLEANUP_READ messages of every text channel and:
#   - deletes its own help messages that are older than HELP_CLOSE_AFTER_MINUTES
#   - for younger ones, starts the timer again for the time that is left
# It runs in its own thread, so the bot answers people while it works.
# Channels Cake can't read (no "Read Message History") are skipped.
require 'time'
require_relative './help_command'
require_relative './discord_history' # ReadingChannel: reads raw JSON, so nobody is looked up per message

HELP_CLEANUP_READ = 100 # messages per channel (one Discord request)
HELP_CLEANUP_STATE = { started: false }

# Discord's "ready" event fires after every reconnect, so only the first one starts the cleanup
def start_help_cleanup_once(bot)
  return if HELP_CLEANUP_STATE[:started]

  HELP_CLEANUP_STATE[:started] = true
  Thread.new { clean_old_help_messages(bot) }
end

# Goes through every text channel of every server
def clean_old_help_messages(bot, now: Time.now, scheduler: HELP_SCHEDULER, deleter: help_deleter(bot))
  channels = bot.servers.values.flat_map(&:text_channels)
  deleted = channels.sum { |channel| clean_help_in_channel(ReadingChannel.new(channel, bot), bot.profile.id, now, scheduler, deleter) }
  log "📘 Deleted #{deleted} old help message(s)" if deleted.positive?
rescue StandardError => e
  log "📘 help cleanup failed (#{e.class}: #{e.message})"
end

# One channel. Returns how many help messages were deleted now.
def clean_help_in_channel(channel, bot_id, now, scheduler, deleter)
  panels = channel.raw_history(HELP_CLEANUP_READ).select { |raw| help_panel?(raw, bot_id) }
  panels.count { |raw| close_left_over_help(channel.id, raw, now, scheduler, deleter) }
rescue StandardError
  0 # can't read this channel: nothing to clean
end

# Cake's own message whose embed is a help page (every help page title starts with HELP_TITLE)
def help_panel?(raw, bot_id)
  return false unless raw.dig("author", "id") == bot_id.to_s

  title = raw["embeds"]&.first&.dig("title").to_s
  title.start_with?(HELP_TITLE)
end

# Deletes it now if its time is up (returns true), or starts its timer again (returns false)
def close_left_over_help(channel_id, raw, now, scheduler, deleter)
  seconds_left = HELP_CLOSE_AFTER_MINUTES * 60 - (now - Time.parse(raw["timestamp"]))
  if seconds_left.positive?
    scheduler.call(seconds_left) { delete_left_over_help(deleter, channel_id, raw["id"]) }
    return false
  end

  delete_left_over_help(deleter, channel_id, raw["id"])
end

# true if it was deleted. Someone may have deleted it already, so a failure is only logged
def delete_left_over_help(deleter, channel_id, message_id)
  deleter.call(channel_id, message_id)
  true
rescue StandardError => e
  log "📘 could not delete a help message (#{e.class}: #{e.message})"
  false
end

# Deletes a message by its ids (we only have the raw JSON, not a discordrb Message)
def help_deleter(bot)
  ->(channel_id, message_id) { Discordrb::API::Channel.delete_message(bot.token, channel_id, message_id) }
end
