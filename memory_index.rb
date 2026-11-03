# MEMORY.md: the list of saved notes for one server. It goes into every prompt, so the AI knows
# what it remembers and can open a note with read_memory. It is always built by code from the
# note files (never written by the AI), so it stays clean even if a note file looks odd.
#
#   ## Upcoming events
#   - events/valorant-cup.md: Valorant Cup, Sat 2026-11-21 20:00
#
#   ## People
#   - users/123.md: Bach (123): likes Valorant
#
# Callers hold with_server_memory_lock; this file does not lock by itself.
require_relative './memory_store'
require_relative './user_notes'
require_relative './event_notes'

MEMORY_INDEX_PATH = "MEMORY.md"

# Build the index, save it as MEMORY.md, and return its text ("" when there is nothing to remember).
# Past events are left out of the index; their files stay on disk.
def rebuild_memory_index(server_id, now = Time.now)
  sections = []
  sections << index_section("## Upcoming events", upcoming_event_lines(server_id, now))
  sections << index_section("## People", people_lines(server_id))
  text = sections.compact.join("\n")
  save_memory_index(server_id, text)
  text
end

# --- helpers ---

# A heading plus its lines, or nil when there are no lines
def index_section(heading, lines)
  return nil if lines.empty?

  "#{heading}\n#{lines.join("\n")}\n"
end

def upcoming_event_lines(server_id, now)
  events = list_event_notes(server_id).reject { |event| event_past?(event[:when], now) }
  events.sort_by { |event| parse_event_time(event[:when]) }.map { |event| event_index_line(event) }
end

def people_lines(server_id)
  list_memory_files(server_id, "users").filter_map do |path|
    user_id = File.basename(path, ".md")
    note = read_user_note(server_id, user_id)
    user_index_line(user_id, note) if note # nil = a file name that isn't allowed (e.g. made by hand)
  end
end

# Don't create a folder for a server that has never saved anything
def save_memory_index(server_id, text)
  return if text.empty? && !Dir.exist?(server_memory_dir(server_id))

  write_memory_file(server_id, MEMORY_INDEX_PATH, text)
end
