# Tool: remember a planned event with a date (a tournament, a meetup, a deadline) for the whole server.
require_relative '../memory_store'
require_relative '../event_notes'
require_relative '../memory_index'

SAVE_EVENT_DEFINITION = {
  type: "function",
  name: "save_event",
  description: "Remember a planned event with a date for this server (a tournament, a meetup, a deadline). " \
               "Use it when someone asks you to remember an event. Saving the same title again updates it.",
  parameters: {
    type: "object",
    properties: {
      title: { type: "string", description: "Short name of the event" },
      when: { type: "string", description: "Date as YYYY-MM-DD, or date and time as YYYY-MM-DD HH:MM (24h, local time)" },
      details: { type: "string", description: "Who, what, where. Can be empty." }
    },
    required: %w[title when details]
  }
}.freeze

def run_save_event(arguments, context)
  return MEMORY_NOT_AVAILABLE if context[:server_id].nil?

  title = arguments["title"].to_s.strip
  return "Error: the event needs a title." if title.empty?

  path = with_server_memory_lock(context[:server_id]) do
    saved = save_event_note(context[:server_id], title, arguments["when"].to_s, arguments["details"].to_s)
    rebuild_memory_index(context[:server_id]) if saved
    saved
  end
  return "Error: 'when' must look like 2026-11-21 or 2026-11-21 20:00." if path.nil?

  log "📅 save_event: #{title} (#{arguments['when']})"
  "Saved event: #{path}"
end
