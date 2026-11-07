# Tool: save a fact about the person who sent the latest message, in their note for this server.
# There is deliberately NO user id parameter: the code fills in who is asking (context[:requester_id]),
# so nobody can make Cake write a note about someone else.
require_relative '../memory_store'
require_relative '../user_notes'
require_relative '../memory_index'

# Optional context for a memory, shared by every tool that writes one
MEMORY_WHY_AND_HOW_PARAMETERS = {
  why: { type: "string", description: "Optional. The reason or what happened, only if it helps use this memory later" },
  how: { type: "string", description: "Optional. When and how to apply it, only if that isn't obvious" }
}.freeze

REMEMBER_ABOUT_ME_DEFINITION = {
  type: "function",
  name: "remember_about_me",
  description: "Save a fact about the person who sent the latest message (their habits, likes, dislikes, " \
               "how they want you to act or talk to them). Use it when they ask you to remember something about " \
               "themselves, tell you how they want you to act, or correct you or are annoyed that you got their " \
               "preference or habit wrong, even if they don't say 'remember'. Use it before promising to act " \
               "differently from now on. It always saves to the sender's own notes. Use it for how they want " \
               "you to refer to other people when talking to them, but not for what they think of other people: " \
               "that goes in remember_about_someone. Check the memory list first: if they already saved the same thing, " \
               "don't call this at all, and if they are changing it, use update_memory instead.",
  parameters: {
    type: "object",
    properties: {
      fact: { type: "string", description: "The fact, short, written about the person (e.g. \"doesn't like anime\")" },
      **MEMORY_WHY_AND_HOW_PARAMETERS
    },
    required: ["fact"]
  }
}.freeze

def run_remember_about_me(arguments, context)
  return MEMORY_NOT_AVAILABLE if context[:server_id].nil?

  fact = text_with_why_and_how(arguments["fact"], arguments)
  problem = check_fact(fact)
  return problem if problem

  log "🧠 remember_about_me for #{context[:requester_name]} (#{context[:requester_id]}): #{fact}"
  with_server_memory_lock(context[:server_id]) do
    append_remembered_fact(context[:server_id], context[:requester_id], context[:requester_name], fact)
    rebuild_memory_index(context[:server_id])
  end
  "Saved to #{context[:requester_name]}'s notes."
end

# "don't guess | why: got Luxio wrong | how: say when unsure". Just the text if there is no why or how.
# "" if the text itself is empty, so a why alone can't become a memory.
def text_with_why_and_how(text, arguments)
  main = one_line(text)
  return "" if main.empty?

  parts = [main]
  %w[why how].each do |key|
    value = one_line(arguments[key])
    parts << "#{key}: #{value}" unless value.empty?
  end
  parts.join(" | ")
end

# An error message for the AI, or nil if the fact is fine
def check_fact(fact)
  return "Error: the fact is empty." if fact.empty?
  return "Error: the fact is too long (max #{REMEMBER_FACT_MAX_CHARS} characters). Make it shorter." if fact.length > REMEMBER_FACT_MAX_CHARS

  nil
end
