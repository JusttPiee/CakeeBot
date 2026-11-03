# Save every message the bot receives to a log file and print it in the terminal,
# with who sent it (name + user ID) and where.
# The file is logs/messages.log, next to cakee.rb. It is ignored by git (*.log in .gitignore).
MESSAGE_LOG_FILE = File.join(__dir__, 'logs', 'messages.log')
MESSAGE_LOG_LOCK = Mutex.new # Messages arrive on different threads, so write one line at a time

# Build one log line, for example:
# [2026-11-03 14:02:11] My Server #general | Piee (123): valorant?
def format_message_log_line(time, place, name, user_id, text)
  one_line_text = text.to_s.gsub("\r", '').gsub("\n", '\\n') # Keep each message on a single line
  "[#{time.strftime('%Y-%m-%d %H:%M:%S')}] #{place} | #{name} (#{user_id}): #{one_line_text}"
end

# Where the message was sent: "Server #channel", or "DM" for private messages
def describe_message_place(event)
  return 'DM' if event.server.nil?

  "#{event.server.name} ##{event.channel.name}"
end

# Add one line to the end of the log file (creates the logs folder the first time)
def append_message_log(line, path = MESSAGE_LOG_FILE)
  MESSAGE_LOG_LOCK.synchronize do
    Dir.mkdir(File.dirname(path)) unless Dir.exist?(File.dirname(path))
    File.open(path, 'a:UTF-8') { |file| file.puts(line) }
  end
end

# Called for every message the bot receives
def log_received_message(event)
  line = format_message_log_line(Time.now, describe_message_place(event),
                                 event.author.display_name, event.author.id, event.message.content)
  puts line # Show it in the terminal too (the line already has a timestamp, like log does)
  append_message_log(line)
rescue StandardError => e
  log "⚠️ Could not write to the message log (#{e.class})." # Never let logging break the bot
end
