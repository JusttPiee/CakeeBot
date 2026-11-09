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
#   ## What people asked you to remember
#   - [a1b2c3d4] Bach (123): call me Boss (2026-11-07)
#
#   ## What people said about others (their opinions, not facts)
#   - [e5f6a7b8] Bach (123) says about Pie (456): is bad at Valorant (2026-11-07)
#
# Callers hold with_server_memory_lock; this file does not lock by itself.
require_relative './memory_store'
require_relative './user_notes'
require_relative './event_notes'
require_relative './memory_items'

MEMORY_INDEX_PATH = "MEMORY.md"

# Build the index, save it as MEMORY.md, and return its text ("" when there is nothing to remember).
# Past events are left out of the index; their files stay on disk.
def rebuild_memory_index(server_id, now = Time.now)
  sections = []
  sections << index_section("## Upcoming events", upcoming_event_lines(server_id, now))
  sections << index_section("## People", people_lines(server_id))
  sections << index_section("## What people asked you to remember", personal_memory_items(server_id).map { |item| personal_item_line(item) })
  sections << index_section("## What people said about others (their opinions, not facts)", general_memory_items(server_id).map { |item| general_item_line(item) })
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
    next if note.nil? # a file name that isn't allowed (e.g. made by hand)

    user_index_line(user_id, note) unless blank_user_note?(note) # e.g. left by !forgetme
  end
end

def personal_item_line(item)
  who = item[:owner_name].to_s.empty? ? "(#{item[:owner_id]})" : "#{item[:owner_name]} (#{item[:owner_id]})"
  "- [#{item[:id]}] #{who}: #{item[:text]}#{item_date_suffix(item)}"
end

def general_item_line(item)
  "- [#{item[:id]}] #{item[:author_name]} (#{item[:author_id]}) says about #{item[:subject_name]} (#{item[:subject_id]}): #{item[:text]}#{item_date_suffix(item)}"
end

def item_date_suffix(item)
  item[:date] ? " (#{item[:date]})" : ""
end

# Don't create a folder for a server that has never saved anything
def save_memory_index(server_id, text)
  return if text.empty? && !Dir.exist?(server_memory_dir(server_id))

  write_memory_file(server_id, MEMORY_INDEX_PATH, text)
end
