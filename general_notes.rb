# General memory: what people said about OTHER people, one file per server: memory/<server_id>/general.md
#
#   - [2026-11-07] from 123 (Bach) about 456 (Pie): is bad at Valorant
#
# Always saved with who said it, because it is that person's opinion, not a fact about the other person.
# Plain text, so it can be edited by hand. Lines that don't look like this are ignored and kept.
require_relative './memory_store'
require_relative './notes_file'

GENERAL_NOTES_PATH = "general.md"
GENERAL_NOTE_LINE = /\A- \[(\d{4}-\d{2}-\d{2})\] from (\d+) \(([^()]*)\) about (\d+) \(([^()]*)\): (.*)\z/

def read_general_lines(server_id)
  read_memory_file(server_id, GENERAL_NOTES_PATH).to_s.gsub("\r", "").split("\n").reject { |line| line.strip.empty? }
end

def write_general_lines(server_id, lines)
  write_memory_file(server_id, GENERAL_NOTES_PATH, lines.map { |line| "#{line}\n" }.join)
end

def append_general_note(server_id, author_id, author_name, subject_id, subject_name, text, now = Time.now)
  line = general_note_line(now.strftime('%Y-%m-%d'), author_id, author_name, subject_id, subject_name, text)
  write_general_lines(server_id, read_general_lines(server_id) + [line])
end

# Names lose their brackets and the text stays on one line, so neither can fake who a note is from or about
def general_note_line(date, author_id, author_name, subject_id, subject_name, text)
  "- [#{date}] from #{author_id} (#{name_for_line(author_name)}) about #{subject_id} (#{name_for_line(subject_name)}): #{one_line(text)}"
end

def name_for_line(name)
  one_line(name).delete("()")
end
