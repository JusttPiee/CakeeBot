# Tool: save what the sender says about ANOTHER person, in the server's general memory, as the sender's opinion.
# The author is filled in by the code (context[:requester_id]), so the AI can't say someone else said it.
require_relative '../memory_store'
require_relative '../general_notes'
require_relative '../memory_index'
require_relative './remember_about_me'

REMEMBER_ABOUT_SOMEONE_DEFINITION = {
  type: "function",
  name: "remember_about_someone",
  description: "Save what the person who sent the latest message thinks or claims about another person. " \
               "It is saved as their opinion, with their name on it, not as a fact about the other person. " \
               "For things about the sender themselves, use remember_about_me instead.",
  parameters: {
    type: "object",
    properties: {
      user_id: { type: "string", description: "The other person's user id, from the chat messages" },
      name: { type: "string", description: "The other person's name" },
      note: { type: "string", description: "What the sender said about them, short (e.g. \"is bad at Valorant\")" },
      **MEMORY_WHY_AND_HOW_PARAMETERS
    },
    required: %w[user_id name note]
  }
}.freeze

def run_remember_about_someone(arguments, context)
  return MEMORY_NOT_AVAILABLE if context[:server_id].nil?

  subject_id = arguments["user_id"].to_s.strip
  note = text_with_why_and_how(arguments["note"], arguments)
  problem = check_note_about_someone(subject_id, note, context) || check_moderation(note, context)
  return problem if problem

  log "🧠 remember_about_someone by #{context[:requester_name]} (#{context[:requester_id]}) about #{subject_id}: #{note}"
  with_server_memory_lock(context[:server_id]) do
    append_general_note(context[:server_id], context[:requester_id], context[:requester_name],
                        subject_id, arguments["name"].to_s, note)
    rebuild_memory_index(context[:server_id])
  end
  "Saved as #{context[:requester_name]}'s opinion."
end

# An error message for the AI, or nil if the note is fine
def check_note_about_someone(subject_id, note, context)
  return "Error: user_id must be the person's numeric user id." unless subject_id.match?(/\A\d+\z/)
  return "Error: that is the sender. Use remember_about_me for things about themselves." if subject_id == context[:requester_id].to_s

  check_fact(note)
end
