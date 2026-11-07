# Tool: replace the personality note the bot wrote about the sender with the version they want.
# There is deliberately NO user id parameter: it can only ever be the person asking (context[:requester_id]).
require_relative '../memory_store'
require_relative '../user_notes'
require_relative '../memory_index'
require_relative './remember_about_me'

UPDATE_MY_PERSONALITY_DEFINITION = {
  type: "function",
  name: "update_my_personality",
  description: "Replace the personality note about the person who sent the latest message. " \
               "Use it when they correct what the note says about them. It only works on the sender's own note.",
  parameters: {
    type: "object",
    properties: {
      new_text: { type: "string", description: "The whole new note, a few short sentences. Keep what is still true" },
      description: { type: "string", description: "The note in at most 10 words" }
    },
    required: %w[new_text description]
  }
}.freeze

def run_update_my_personality(arguments, context)
  return MEMORY_NOT_AVAILABLE if context[:server_id].nil?

  new_text = arguments["new_text"].to_s.strip
  problem = check_fact(new_text)
  return problem if problem

  log "🧠 update_my_personality by #{context[:requester_name]} (#{context[:requester_id]}): #{new_text}"
  with_server_memory_lock(context[:server_id]) do
    change_user_personality(context[:server_id], context[:requester_id], context[:requester_name], new_text, arguments["description"].to_s)
    rebuild_memory_index(context[:server_id])
  end
  "Personality note updated."
end
