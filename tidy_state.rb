# What tidying remembers about each person in a server, so a restart doesn't repeat work or questions.
# Saved as JSON in memory/<server_id>/tidy_state.md (memory files must end in .md):
#   tidied:   fingerprint of their facts after the last tidy, so facts that are already fine aren't reworded
#   checked:  fingerprint of their facts plus related memories at the last conflict check
#   check_failed_at: when the last conflict check failed, so it can be tried again later
#   channel:  where they last talked with the bot, so a question can be sent there
#   memory_questions.rb keeps its question values here too
#
# Every method takes the server's memory lock, so don't call them while holding it.
require 'json'
require_relative './memory_store'

TIDY_STATE_PATH = "tidy_state.md"

def tidy_state_of(server_id, user_id)
  with_server_memory_lock(server_id) { read_tidy_state(server_id)[user_id.to_s] || {} }
end

# Changes some values for this person. A nil value removes that value. Nothing is written if nothing changed.
def update_tidy_state(server_id, user_id, changes)
  with_server_memory_lock(server_id) do
    state = read_tidy_state(server_id)
    old_entry = state[user_id.to_s] || {}
    new_entry = old_entry.merge(changes.transform_keys(&:to_s)).compact
    next if new_entry == old_entry

    state[user_id.to_s] = new_entry
    write_memory_file(server_id, TIDY_STATE_PATH, JSON.pretty_generate(state))
  end
end

def remember_last_channel(server_id, user_id, channel_id)
  update_tidy_state(server_id, user_id, channel: channel_id)
end

def last_channel_of(server_id, user_id)
  tidy_state_of(server_id, user_id)["channel"]
end

# Forget everything tidying knew about this person (used by !forgetme)
def forget_tidy_state(server_id, user_id)
  with_server_memory_lock(server_id) do
    state = read_tidy_state(server_id)
    next unless state.key?(user_id.to_s)

    state.delete(user_id.to_s)
    write_memory_file(server_id, TIDY_STATE_PATH, JSON.pretty_generate(state))
  end
end

# --- helpers ---

# Only changed by the code, but a broken file must not stop the bot: it just means starting over
def read_tidy_state(server_id)
  state = JSON.parse(read_memory_file(server_id, TIDY_STATE_PATH).to_s)
  state.is_a?(Hash) ? state : {}
rescue JSON::ParserError
  {}
end
