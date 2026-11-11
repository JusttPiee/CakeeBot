# Turns memory notes into plain Hashes for the web page (they become JSON).
# The shapes are the API contract: the React app's types in web/src/api/types.ts match them.
require_relative '../user_notes'
require_relative '../memory_items'

# One row in the list of people
def user_summary_view(user_id, note)
  { id: user_id.to_s, name: note[:name], description: note[:description],
    fact_count: note[:remembered].length, personality_off: note[:personality_off] }
end

# The whole note, for the form. Each fact gets the same id the AI tools use (see memory_items.rb).
def user_note_view(user_id, note)
  { id: user_id.to_s, name: note[:name], description: note[:description], personality: note[:personality],
    personality_off: note[:personality_off], facts: note[:remembered].map { |fact| fact_view(user_id, note[:name], fact) } }
end

def fact_view(user_id, name, fact)
  item = personal_memory_item(user_id.to_s, name, fact)
  { id: item[:id], date: item[:date], text: item[:text] }
end

# One line of general.md: who said what about whom
def general_item_view(item)
  { id: item[:id], date: item[:date], author_id: item[:author_id], author_name: item[:author_name],
    subject_id: item[:subject_id], subject_name: item[:subject_name], text: item[:text] }
end

# event: one entry of list_event_notes. The slug is the file name, e.g. "valorant-cup" for events/valorant-cup.md.
def event_view(event, now = Time.now)
  { slug: File.basename(event[:path], ".md"), title: event[:title], when: event[:when],
    details: event[:details], past: event_past?(event[:when], now) }
end

# note: a parsed channel summary file (see channel_summary.rb). The name is "" when the channel no longer exists.
def summary_view(channel_id, channel_name, note)
  { channel_id: channel_id.to_s, channel_name: channel_name.to_s,
    updated: note[:headers]["updated"].to_s, text: note[:body] }
end
