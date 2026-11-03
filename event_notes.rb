# Planned events with a date (a tournament, a meetup...): memory/<server_id>/events/<slug>.md
#
#   title: Valorant tournament
#   when: 2026-11-21 20:00
#
#   Bach hosts, bring snacks.
#
# "when" is always YYYY-MM-DD or YYYY-MM-DD HH:MM (the bot's local time), so the code can tell
# when an event has passed. Past events are hidden from MEMORY.md, but their files are kept.
require 'time'
require_relative './memory_store'
require_relative './notes_file'

EVENT_TIME_FORMAT = /\A\d{4}-\d{2}-\d{2}( \d{2}:\d{2})?\z/
EVENT_SLUG_MAX_LENGTH = 50

# "2026-11-21" or "2026-11-21 20:00" => Time. Anything else (or an impossible date) => nil
def parse_event_time(text)
  text = text.to_s.strip
  return nil unless EVENT_TIME_FORMAT.match?(text)

  format = text.length > 10 ? "%Y-%m-%d %H:%M" : "%Y-%m-%d"
  time = Time.strptime(text, format)
  time.strftime(format) == text ? time : nil # strptime quietly turns 2026-02-30 into March 2nd
rescue ArgumentError
  nil
end

# "Giải đấu Valorant!" => "giải-đấu-valorant" (letters of any language are kept)
def event_slug(title)
  slug = title.to_s.downcase.gsub(/[^\p{L}\p{N}]+/, "-").gsub(/\A-+|-+\z/, "")
  slug = slug[0, EVENT_SLUG_MAX_LENGTH].sub(/-+\z/, "")
  slug.empty? ? "event" : slug
end

# Save (or update, if the title is the same) an event. Returns its path, or nil if "when" is not valid.
def save_event_note(server_id, title, when_text, details)
  return nil if parse_event_time(when_text).nil?

  path = "events/#{event_slug(title)}.md"
  write_memory_file(server_id, path, format_note({ "title" => title, "when" => when_text.strip }, details))
  path
end

# Every event with a valid date: [{ path:, title:, when:, details: }]
def list_event_notes(server_id)
  events = list_memory_files(server_id, "events").map do |path|
    note = parse_note(read_memory_file(server_id, path))
    { path: path, title: note[:headers]["title"].to_s, when: note[:headers]["when"].to_s, details: note[:body] }
  end
  events.select { |event| parse_event_time(event[:when]) }
end

# A date-only event counts as past once that whole day is over
def event_past?(when_text, now = Time.now)
  time = parse_event_time(when_text)
  time += 24 * 3600 if when_text.strip.length == 10
  time < now
end

# The line for MEMORY.md, e.g. "- events/valorant-cup.md: Valorant Cup, Sat 2026-11-21 20:00"
def event_index_line(event)
  day = parse_event_time(event[:when]).strftime("%a")
  "- #{event[:path]}: #{event[:title]}, #{day} #{event[:when]}"
end
