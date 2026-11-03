# Tool: save a fact about the person who sent the latest message, in their note for this server.
# There is deliberately NO user id parameter: the code fills in who is asking (context[:requester_id]),
# so nobody can make Cake write a note about someone else.
require_relative '../memory_store'
require_relative '../user_notes'
require_relative '../memory_index'

REMEMBER_ABOUT_ME_DEFINITION = {
  type: "function",
  name: "remember_about_me",
  description: "Save a fact about the person who sent the latest message (their habits, likes, dislikes, " \
               "how they want to be treated). Use it when they ask you to remember something about themselves, " \
               "or when they correct you or are annoyed that you got their preference or habit wrong, even if " \
               "they don't say 'remember'. It always saves to the sender's own notes. Never use it for facts " \
               "about other people: if someone asks you to remember something about another person, say you can't.",
  parameters: {
    type: "object",
    properties: {
      fact: { type: "string", description: "The fact, short, written about the person (e.g. \"doesn't like anime\")" }
    },
    required: ["fact"]
  }
}.freeze

def run_remember_about_me(arguments, context)
  return MEMORY_NOT_AVAILABLE if context[:server_id].nil?

  fact = arguments["fact"].to_s.strip
  problem = check_fact(fact)
  return problem if problem

  log "🧠 remember_about_me for #{context[:requester_name]} (#{context[:requester_id]}): #{fact}"
  with_server_memory_lock(context[:server_id]) do
    append_remembered_fact(context[:server_id], context[:requester_id], context[:requester_name], fact)
    rebuild_memory_index(context[:server_id])
  end
  "Saved to #{context[:requester_name]}'s notes."
end

# An error message for the AI, or nil if the fact is fine
def check_fact(fact)
  return "Error: the fact is empty." if fact.empty?
  return "Error: the fact is too long (max #{REMEMBER_FACT_MAX_CHARS} characters). Make it shorter." if fact.length > REMEMBER_FACT_MAX_CHARS

  nil
end
