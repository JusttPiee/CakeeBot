# Tool: remove one saved memory. People can remove what they saved, and what was saved about them
# (checked in memory_items.rb, using who is asking from Discord).
require_relative '../memory_store'
require_relative '../memory_items'
require_relative '../memory_index'
require_relative './update_memory'

FORGET_MEMORY_DEFINITION = {
  type: "function",
  name: "forget_memory",
  description: "Remove one saved memory, using the id in square brackets from the memory list. " \
               "Use it when someone asks you to forget or remove it. People can remove what they saved " \
               "and anything that was saved about them.",
  parameters: {
    type: "object",
    properties: {
      memory_id: { type: "string", description: "The id from the memory list, without the brackets" }
    },
    required: ["memory_id"]
  }
}.freeze

def run_forget_memory(arguments, context)
  return MEMORY_NOT_AVAILABLE if context[:server_id].nil?

  with_server_memory_lock(context[:server_id]) do
    item = find_memory_item(context[:server_id], arguments["memory_id"])
    next memory_not_found(arguments["memory_id"]) if item.nil?
    unless can_remove_memory?(item, context[:requester_id])
      log_refused_memory_change("forget_memory", context, item[:text])
      next "Error: people can only remove what they saved or what was saved about them."
    end

    log "🧠 forget_memory by #{context[:requester_name]} (#{context[:requester_id]}): #{item[:text]}"
    remove_memory_item(context[:server_id], item)
    rebuild_memory_index(context[:server_id])
    "Memory removed."
  end
end
