# Tool: remove the personality note the bot wrote about the sender, and stop it from being written again.
# There is deliberately NO user id parameter: it can only ever be the person asking (context[:requester_id]).
require_relative '../memory_store'
require_relative '../user_notes'
require_relative '../memory_index'

FORGET_MY_PERSONALITY_DEFINITION = {
  type: "function",
  name: "forget_my_personality",
  description: "Remove the personality note about the person who sent the latest message, and stop keeping one. " \
               "Use it when they ask you to remove it, or to stop noting what they are like. " \
               "Their saved memories stay. It only works on the sender's own note.",
  parameters: { type: "object", properties: {} }
}.freeze

def run_forget_my_personality(_arguments, context)
  return MEMORY_NOT_AVAILABLE if context[:server_id].nil?

  log "🧠 forget_my_personality by #{context[:requester_name]} (#{context[:requester_id]})"
  with_server_memory_lock(context[:server_id]) do
    remove_user_personality(context[:server_id], context[:requester_id], context[:requester_name])
    rebuild_memory_index(context[:server_id])
  end
  "Personality note removed. It won't be written again unless they ask."
end
