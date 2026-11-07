# One list of everything people asked the bot to remember: personal facts (users/<id>.md, "Asked to remember")
# and general notes (general.md). Each item gets a short id so the AI can change or remove exactly that one.
#
# Who may do what is decided here, in code, never by the AI:
#   change: only whoever saved it
#   remove: whoever saved it, the person a general note is about, and anyone whose user id is in the text
#
# Callers hold with_server_memory_lock; this file does not lock by itself.
require 'digest'
require_relative './user_notes'
require_relative './general_notes'

FACT_LINE = /\A\[([^\]]*)\] (.*)\z/

def all_memory_items(server_id)
  personal_memory_items(server_id) + general_memory_items(server_id)
end

def find_memory_item(server_id, id)
  all_memory_items(server_id).find { |item| item[:id] == id.to_s.strip }
end

def can_change_memory?(item, requester_id)
  saved_by(item) == requester_id.to_s
end

def can_remove_memory?(item, requester_id)
  requester = requester_id.to_s
  can_change_memory?(item, requester) || item[:subject_id] == requester || item[:text].scan(/\d+/).include?(requester)
end

def change_memory_item(server_id, item, new_text, now = Time.now)
  date = now.strftime('%Y-%m-%d')
  if item[:kind] == :personal
    edit_personal_facts(server_id, item) { |facts| facts.map { |fact| fact == item[:raw] ? "[#{date}] #{one_line(new_text)}" : fact } }
  else
    new_line = general_note_line(date, item[:author_id], item[:author_name], item[:subject_id], item[:subject_name], new_text)
    write_general_lines(server_id, read_general_lines(server_id).map { |line| line == item[:raw] ? new_line : line })
  end
end

def remove_memory_item(server_id, item)
  if item[:kind] == :personal
    edit_personal_facts(server_id, item) { |facts| facts.reject { |fact| fact == item[:raw] } }
  else
    write_general_lines(server_id, read_general_lines(server_id).reject { |line| line == item[:raw] })
  end
end

# The first memory becomes the new text, the others are removed.
# The caller has checked that they all have the same owner and kind (tools/merge_memories.rb).
# The others go first: if the new text is the same as one of them, removing it afterwards would remove the new one too.
def merge_memory_items(server_id, items, new_text, now = Time.now)
  items.drop(1).each { |item| remove_memory_item(server_id, item) }
  change_memory_item(server_id, items.first, new_text, now)
end

# Several personal facts of one person become one or more new facts (tidying can also split a fact with two ideas).
# They keep the newest date of the old facts: rewording a fact doesn't make the fact itself newer.
def replace_memory_items(server_id, items, new_texts)
  date = newest_item_date(items)
  merge_memory_items(server_id, items, new_texts.first, date)
  new_texts.drop(1).each { |text| append_remembered_fact(server_id, items.first[:owner_id], items.first[:owner_name], text, date) }
end

# A Time, or today if none of the items has a proper date (e.g. a line written by hand)
def newest_item_date(items)
  dates = items.map { |item| item[:date].to_s }.grep(/\A\d{4}-\d{2}-\d{2}\z/)
  dates.empty? ? Time.now : Time.new(*dates.max.split("-").map(&:to_i))
end

# --- helpers ---

def saved_by(item)
  item[:kind] == :personal ? item[:owner_id] : item[:author_id]
end

def personal_memory_items(server_id)
  list_memory_files(server_id, "users").flat_map do |path|
    user_id = File.basename(path, ".md")
    note = read_user_note(server_id, user_id)
    note.nil? ? [] : note[:remembered].map { |fact| personal_memory_item(user_id, note[:name], fact) }
  end
end

def personal_memory_item(user_id, name, fact)
  match = FACT_LINE.match(fact)
  { id: memory_item_id(user_id, fact), kind: :personal, owner_id: user_id, owner_name: name, raw: fact,
    date: match && match[1], text: match ? match[2] : fact }
end

def general_memory_items(server_id)
  read_general_lines(server_id).filter_map do |line|
    match = GENERAL_NOTE_LINE.match(line)
    next if match.nil? # a line written by hand

    { id: memory_item_id("general", line), kind: :general, raw: line, date: match[1],
      author_id: match[2], author_name: match[3], subject_id: match[4], subject_name: match[5], text: match[6] }
  end
end

# Made from the saved line, so old facts have an id too and nothing extra is stored in the files
def memory_item_id(scope, line)
  Digest::SHA1.hexdigest("#{scope}|#{line}")[0, 8]
end

def edit_personal_facts(server_id, item)
  note = read_user_note(server_id, item[:owner_id])
  note[:remembered] = yield(note[:remembered])
  write_user_note(server_id, item[:owner_id], note)
end
