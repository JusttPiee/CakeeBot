# Tool: open one memory note listed in MEMORY.md (e.g. "users/123.md").
# Only files inside this server's memory folder can be read (memory_store.rb checks the path).
require_relative '../memory_store'

READ_MEMORY_DEFINITION = {
  type: "function",
  name: "read_memory",
  description: "Open one of your saved memory notes for this server, using a path from the memory index " \
               "(for example users/123.md or events/valorant-cup.md).",
  parameters: {
    type: "object",
    properties: {
      path: { type: "string", description: "The path exactly as shown in the memory index" }
    },
    required: ["path"]
  }
}.freeze

def run_read_memory(arguments, context)
  return MEMORY_NOT_AVAILABLE if context[:server_id].nil?

  path = arguments["path"].to_s.strip
  log "🔎 read_memory by #{context[:requester_name]} (#{context[:requester_id]}): #{path}"
  # Channel summaries stay private to their own channel (a mod channel's summary must not leak).
  # The current channel's summary is already in the prompt, so the AI never needs to open one.
  return "Error: channel summaries can't be opened with read_memory." if path.start_with?("channels/")

  text = read_memory_file(context[:server_id], path)
  return "Error: there is no memory note at #{path}." if text.nil?

  text
end
