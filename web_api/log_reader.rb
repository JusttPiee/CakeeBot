# Reads the bot's log files for the web UI's Logs page.
# The files are written by message_logger.rb: one folder per day, one file per hour (logs/2026-11-07/14.log).
#
# A day's lines are numbered in order, across its hour files. The page remembers how many lines it has
# (the "cursor") and asks only for the lines after that, so following the log live stays cheap.
require_relative '../message_logger'

LOG_PAGE_LINES = 2000 # the first read of a day gives only its last lines; a busy day has many more
LOG_DAY_FORMAT = /\A\d{4}-\d{2}-\d{2}\z/
LOG_LINE = /\A\[\d{4}-\d{2}-\d{2} (\d{2}:\d{2}:\d{2})\] (.*)\z/m
# "My Server #general | Piee (123): valorant?" (see format_message_log_line)
LOG_CHAT_PART = /\A(.+?) \| (.+?) \((\d+)\): (.*)\z/m

# The days that have logs, newest first: ["2026-11-11", "2026-11-10"]
def log_days(log_dir = MESSAGE_LOG_DIR)
  return [] unless File.directory?(log_dir)

  days = Dir.children(log_dir).select { |name| LOG_DAY_FORMAT.match?(name) && File.directory?(File.join(log_dir, name)) }
  days.sort.reverse
end

# { cursor: how many lines the day has now, lines: [...] }
# after = how many lines the page already has. nil (the first read) gives the last LOG_PAGE_LINES lines.
def read_log_lines(day, after, log_dir = MESSAGE_LOG_DIR)
  lines = day_log_lines(day, log_dir)
  { cursor: lines.length, lines: lines.drop(first_log_line(lines.length, after)).map { |line| parse_log_line(line) } }
end

def first_log_line(total, after)
  return [total - LOG_PAGE_LINES, 0].max if after.nil?

  after > total ? 0 : after # more than there is: the files were replaced, so start over
end

# Every line of one day, oldest first
def day_log_lines(day, log_dir)
  hour_files = Dir.glob(File.join(log_dir, day, "[0-2][0-9].log")).sort
  hour_files.flat_map { |file| read_log_file(file) }
end

# scrub: a line with broken bytes gets "?" for them, instead of breaking the whole page
def read_log_file(file)
  File.read(file, encoding: "UTF-8").scrub("?").split("\n").reject(&:empty?)
end

# One line as { time:, kind:, place:, text: }.
# kind "chat" is a message someone sent (place = where, text = "name: message"); everything else is "system".
def parse_log_line(line)
  match = LOG_LINE.match(line)
  return { time: "", kind: "system", place: "", text: line } if match.nil?

  chat = LOG_CHAT_PART.match(match[2])
  return { time: match[1], kind: "system", place: "", text: match[2] } if chat.nil?

  { time: match[1], kind: "chat", place: chat[1], text: "#{chat[2]}: #{chat[4]}" }
end
