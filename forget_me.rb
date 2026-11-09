# !forgetme: a person removes everything Cake remembers about them in this server.
#   - their note users/<id>.md: the personality note and everything they asked Cake to remember
#   - general notes they saved about others, and that others saved about them (general.md)
#   - other people's saved facts that mention their user id
#   - what tidying knew about them (questions, fingerprints) in tidy_state.md
#
# Their note file is then replaced by a blank one with only "personality_off: yes", so compaction and
# !buildmemory won't write a new personality note about them (blank notes are hidden from MEMORY.md).
# If they later ask Cake to remember something, or write their personality note themselves
# (update_my_personality), that is their own choice and it works as usual.
#
# Not touched: channel summaries (they are about conversations, not one person, and shrink over time)
# and events (plans of the whole server).
require_relative './memory_store'
require_relative './memory_items'
require_relative './memory_index'
require_relative './user_notes'
require_relative './tidy_state'

FORGET_ME_CONFIRM_WORD = "confirm"

# What would be removed: { facts: count, personality: true/false, shared: count }
def forget_me_preview(server_id, user_id)
  with_server_memory_lock(server_id) do
    note = read_user_note(server_id, user_id)
    { facts: note ? note[:remembered].length : 0,
      personality: note ? !note[:personality].empty? : false,
      shared: shared_memories_to_forget(server_id, user_id).length }
  end
end

# Removes it all. Returns what was removed, like forget_me_preview.
def forget_user(server_id, user_id)
  removed = forget_me_preview(server_id, user_id)
  with_server_memory_lock(server_id) do
    shared_memories_to_forget(server_id, user_id).each { |item| remove_memory_item(server_id, item) }
    delete_memory_file(server_id, user_note_path(user_id))
    remove_user_personality(server_id, user_id, "") # the blank note that stops new personality notes
    rebuild_memory_index(server_id)
  end
  forget_tidy_state(server_id, user_id)
  removed
end

# General notes from or about them, and other people's facts that mention their id.
# The same rule as forget_memory (can_remove_memory?). Their own facts are not in this list:
# they are deleted together with their note file.
def shared_memories_to_forget(server_id, user_id)
  all_memory_items(server_id).select do |item|
    item[:owner_id] != user_id.to_s && can_remove_memory?(item, user_id)
  end
end

# --- the Discord command ---

# !forgetme shows what would be removed; !forgetme confirm removes it
def forget_me_command(event, word)
  return event.respond("❗ `!forgetme` only works in a server.") if event.server.nil?

  server_id = event.server.id
  user_id = event.author.id
  if word.to_s.strip.downcase == FORGET_ME_CONFIRM_WORD
    removed = forget_user(server_id, user_id)
    log "🧹 !forgetme by #{event.author.display_name} (#{user_id}) in #{event.server.name}: #{removed.inspect}"
    event.respond("🧹 Done <@#{user_id}>, I forgot everything I remembered about you in this server.")
  else
    event.respond(forget_me_preview_text(user_id, forget_me_preview(server_id, user_id)))
  end
end

def forget_me_preview_text(user_id, preview)
  <<~TEXT.strip
    <@#{user_id}> this deletes everything I remember about you in this server:
    - my personality note about you: #{preview[:personality] ? 'yes' : 'none'}
    - things you asked me to remember: #{preview[:facts]}
    - notes you saved about others, or others saved about you: #{preview[:shared]}
    After that I won't write a new personality note about you. This can't be undone.
    Type `!forgetme #{FORGET_ME_CONFIRM_WORD}` to do it.
  TEXT
end
