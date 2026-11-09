# Tool: search this server's memory by meaning. Finds things the memory index doesn't show
# (what is inside a person's note, past events), or that use other words than the question.
require_relative '../memory_store'
require_relative '../memory_search'

SEARCH_MEMORY_DEFINITION = {
  type: "function",
  name: "search_memory",
  description: "Search everything saved in your memory for this server by meaning, not exact words. " \
               "Use it when someone asks about something you might have saved but the memory index doesn't show it, " \
               "for example details inside a person's note or a past event. Open a found note with read_memory if you need all of it.",
  parameters: {
    type: "object",
    properties: {
      query: { type: "string", description: "What you are looking for, in a few words (e.g. \"Bach's cat\")" }
    },
    required: ["query"]
  }
}.freeze

def run_search_memory(arguments, context)
  return MEMORY_NOT_AVAILABLE if context[:server_id].nil? || context[:client].nil?

  query = arguments["query"].to_s.strip
  return "Error: the query is empty." if query.empty?

  log "🔎 search_memory by #{context[:requester_name]} (#{context[:requester_id]}): #{query}"
  search_memory(context[:client], context[:server_id], query[0, EMBEDDING_MAX_CHARS])
end
