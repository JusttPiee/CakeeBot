# Save what happens to log files: messages the bot receives, its AI replies, and status lines.
# One file per hour, in one folder per day: logs/2026-11-07/14.log (ignored by git, *.log in .gitignore).
# Tests point this at a temp folder. Keep this file free of config.rb: cakee.rb needs it before .env is loaded.
require 'fileutils'

MESSAGE_LOG_DIR = ENV['CAKE_TEST_LOG_DIR'] || File.join(__dir__, 'logs')
MESSAGE_LOG_LOCK = Mutex.new # Messages arrive on different threads, so write one line at a time

def format_log_time(time)
  time.strftime('%Y-%m-%d %H:%M:%S')
end

# Keep each entry on a single line
def to_one_line(text)
  text.to_s.gsub("\r", '').gsub("\n", '\\n')
end

# Build one log line, for example:
# [2026-11-03 14:02:11] My Server #general | Piee (123): valorant?
def format_message_log_line(time, place, name, user_id, text)
  "[#{format_log_time(time)}] #{place} | #{name} (#{user_id}): #{to_one_line(text)}"
end

# Where the message was sent: "Server #channel", or "DM" for private messages
def describe_message_place(event)
  return 'DM' if event.server.nil?

  "#{event.server.name} ##{event.channel.name}"
end

# Which file an entry from this time belongs in, for example logs/2026-11-07/14.log
def message_log_path(time, log_dir = MESSAGE_LOG_DIR)
  File.join(log_dir, time.strftime('%Y-%m-%d'), "#{time.strftime('%H')}.log")
end

# Add one line to the end of the log file (creates the folders the first time)
def append_message_log(line, path)
  MESSAGE_LOG_LOCK.synchronize do
    FileUtils.mkdir_p(File.dirname(path))
    File.open(path, 'a:UTF-8') { |file| file.puts(line) }
  end
end

# Called for every message the bot receives
def log_received_message(event, time = Time.now, log_dir = MESSAGE_LOG_DIR)
  line = format_message_log_line(time, describe_message_place(event),
                                 event.author.display_name, event.author.id, event.message.content)
  puts line # Show it in the terminal too (the line already has a timestamp, like log does)
  append_message_log(line, message_log_path(time, log_dir))
rescue StandardError => e
  log "⚠️ Could not write to the message log (#{e.class})." # Never let logging break the bot
end

# Called after an AI reply is sent. The file only: long replies would flood the terminal.
def log_bot_reply(event, text, time = Time.now, log_dir = MESSAGE_LOG_DIR)
  line = format_message_log_line(time, describe_message_place(event),
                                 event.server.bot.display_name, event.bot.profile.id, text)
  append_message_log(line, message_log_path(time, log_dir))
rescue StandardError => e
  log "⚠️ Could not write the bot's reply to the log (#{e.class})." # Never let logging break the bot
end

# What log (in cakee.rb) does: a timestamped status line in the terminal and in the file.
# If the file fails this only prints a warning, because calling log here would loop forever.
def log_status_line(message, time = Time.now, log_dir = MESSAGE_LOG_DIR)
  line = "[#{format_log_time(time)}] #{message}"
  puts line
  append_message_log(to_one_line(line), message_log_path(time, log_dir))
rescue StandardError => e
  puts "[#{format_log_time(time)}] ⚠️ Could not write to the log file (#{e.class})."
end
