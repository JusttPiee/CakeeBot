# What Cake remembers about one person, in one server: memory/<server_id>/users/<user_id>.md
#
#   name: Bach
#   description: likes Valorant, studies CS
#
#   ## Personality
#   Plays Valorant most nights...
#
#   ## Asked to remember
#   - [2026-11-04] doesn't like anime
#
# Two writers, each with its own part:
# - compaction rewrites "Personality" (and the description), from that person's own messages only
# - remember_about_me adds lines to "Asked to remember"; compaction never touches them
#
# Personality is the bot's guess, so its owner decides: update_my_personality changes it, and
# forget_my_personality removes it and adds a "personality_off: yes" header so compaction can't write it again.
require_relative './memory_store'
require_relative './notes_file'

PERSONALITY_HEADING = "## Personality"
REMEMBERED_HEADING = "## Asked to remember"

def user_note_path(user_id)
  "users/#{user_id}.md"
end

# { name:, description:, personality:, remembered: [...] }, or nil if there is no note yet
def read_user_note(server_id, user_id)
  text = read_memory_file(server_id, user_note_path(user_id))
  return nil if text.nil?

  note = parse_note(text)
  personality, remembered = split_user_sections(note[:body])
  { name: note[:headers]["name"].to_s, description: note[:headers]["description"].to_s,
    personality: personality, remembered: remembered, personality_off: note[:headers]["personality_off"] == "yes" }
end

# Add one fact the person asked Cake to remember, with today's date.
# The fact is flattened to one line, so it can't pretend to be a new section.
def append_remembered_fact(server_id, user_id, name, fact, now = Time.now)
  note = read_user_note(server_id, user_id) || empty_user_note
  note[:name] = name
  note[:remembered] << "[#{now.strftime('%Y-%m-%d')}] #{one_line(fact)}"
  write_user_note(server_id, user_id, note)
end

# Replace the Personality section and the one-line description. Remembered facts stay.
# Does nothing if the person removed their personality note.
def write_user_personality(server_id, user_id, name, personality, description)
  note = read_user_note(server_id, user_id) || empty_user_note
  return if note[:personality_off]

  save_user_personality(server_id, user_id, note, name, personality, description)
end

# The person's own new version. If they had removed their note, this turns it back on.
def change_user_personality(server_id, user_id, name, personality, description)
  note = read_user_note(server_id, user_id) || empty_user_note
  note[:personality_off] = false
  save_user_personality(server_id, user_id, note, name, personality, description)
end

# Remove the note, and stop compaction from writing it again
def remove_user_personality(server_id, user_id, name)
  note = read_user_note(server_id, user_id) || empty_user_note
  note[:personality_off] = true
  save_user_personality(server_id, user_id, note, name, "", "")
end

# The line for MEMORY.md, e.g. "- users/123.md: Bach (123): likes Valorant".
# No description yet (only remember_about_me used)? Then the latest remembered fact is shown.
def user_index_line(user_id, note)
  who = note[:name].to_s.empty? ? "(#{user_id})" : "#{note[:name]} (#{user_id})"
  about = note[:description].to_s.empty? ? latest_fact(note) : note[:description]
  line = "- #{user_note_path(user_id)}: #{who}"
  about.to_s.empty? ? line : "#{line}: #{about}"
end

# A note with nothing in it, like the one !forgetme leaves (only "personality_off: yes").
# It is not shown in MEMORY.md, because there is nobody to remember.
def blank_user_note?(note)
  note[:name].to_s.empty? && note[:description].to_s.empty? && note[:personality].to_s.empty? && note[:remembered].empty?
end

# --- helpers ---

def empty_user_note
  { name: "", description: "", personality: "", remembered: [], personality_off: false }
end

def save_user_personality(server_id, user_id, note, name, personality, description)
  note[:name] = name
  note[:personality] = without_headings(personality)
  note[:description] = description
  write_user_note(server_id, user_id, note)
end

def write_user_note(server_id, user_id, note)
  headers = { "name" => note[:name], "description" => note[:description] }
  headers["personality_off"] = "yes" if note[:personality_off]
  write_memory_file(server_id, user_note_path(user_id), format_note(headers, user_note_body(note)))
end

def user_note_body(note)
  facts = note[:remembered].map { |fact| "- #{fact}" }.join("\n")
  "#{PERSONALITY_HEADING}\n#{note[:personality]}\n\n#{REMEMBERED_HEADING}\n#{facts}"
end

# Body text => [personality text, list of remembered facts]
def split_user_sections(body)
  # The heading only counts on a line of its own, so "## Asked to remember" inside a sentence can't forge facts
  personality_part, remembered_part = body.split(/^#{Regexp.escape(REMEMBERED_HEADING)}[ \t]*$/, 2)
  personality = personality_part.to_s.sub(PERSONALITY_HEADING, "").strip
  facts = remembered_part.to_s.lines.map(&:strip).select { |line| line.start_with?("- ") }
  [personality, facts.map { |line| line.delete_prefix("- ") }]
end

# Personality text comes from the AI. Markdown headings are removed, so it can't start a fake section.
def without_headings(text)
  text.to_s.gsub(/^\s*#+\s*/, "").strip
end

# "[2026-11-04] doesn't like anime" => "doesn't like anime"
def latest_fact(note)
  note[:remembered].last.to_s.sub(/\A\[[^\]]*\] /, "")
end
