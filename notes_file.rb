# The file format shared by every memory note (users, events, channel summaries).
# A note is a few "key: value" header lines, a blank line, then the text:
#
#   title: Valorant tournament
#   when: 2026-11-21 20:00
#
#   Bach hosts, bring snacks.
#
# Files are plain text, so the user can open and edit them by hand.

HEADER_LINE = /\A([a-z_]+): (.*)\z/

# Text => { headers: { "title" => "..." }, body: "..." }
# If the first line is not a header (a hand-written file), the whole text is the body.
def parse_note(text)
  lines = text.to_s.delete_prefix("﻿").gsub("\r", "").split("\n") # ﻿: a mark some editors add at the start
  headers = {}
  while lines.any? && (match = HEADER_LINE.match(lines.first))
    headers[match[1]] = match[2].strip
    lines.shift
  end
  { headers: headers, body: lines.join("\n").strip }
end

# The opposite of parse_note. Header values are kept on one line, or they would break the format.
def format_note(headers, body)
  header_lines = headers.map { |key, value| "#{key}: #{one_line(value)}\n" }.join
  "#{header_lines}\n#{body.to_s.strip}\n"
end

def one_line(text)
  text.to_s.gsub(/\s+/, " ").strip
end
