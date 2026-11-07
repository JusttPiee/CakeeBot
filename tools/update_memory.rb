# Tool: replace one saved memory with a new version, so a changed fact doesn't pile up next to the old one.
# Only whoever saved it can change it (checked in memory_items.rb, using who is asking from Discord).
require_relative '../memory_store'
require_relative '../memory_items'
require_relative '../memory_index'
require_relative './remember_about_me'

UPDATE_MEMORY_DEFINITION = {
  type: "function",
  name: "update_memory",
  description: "Replace one saved memory with a new version, using the id in square brackets from the memory list. " \
               "Use it when the sender changes or refines something they already saved, instead of saving it again. " \
               "It only works on what the sender saved themselves.",
  parameters: {
    type: "object",
    properties: {
      memory_id: { type: "string", description: "The id from the memory list, without the brackets" },
      new_text: { type: "string", description: "The whole new version of the memory, short, without why and how" },
      **MEMORY_WHY_AND_HOW_PARAMETERS
    },
    required: %w[memory_id new_text]
  }
}.freeze

def run_update_memory(arguments, context)
  return MEMORY_NOT_AVAILABLE if context[:server_id].nil?

  new_text = text_with_why_and_how(arguments["new_text"], arguments)
  problem = check_fact(new_text)
  return problem if problem

  with_server_memory_lock(context[:server_id]) do
    item = find_memory_item(context[:server_id], arguments["memory_id"])
    next memory_not_found(arguments["memory_id"]) if item.nil?
    unless can_change_memory?(item, context[:requester_id])
      log_refused_memory_change("update_memory", context, item[:text])
      next "Error: only the person who saved this memory can change it. They can remove it if it mentions them."
    end

    log "🧠 update_memory by #{context[:requester_name]} (#{context[:requester_id]}): #{item[:text]} => #{new_text}"
    change_memory_item(context[:server_id], item, new_text)
    rebuild_memory_index(context[:server_id])
    "Memory updated."
  end
end

def log_refused_memory_change(tool_name, context, details)
  log "🚫 #{tool_name} refused for #{context[:requester_name]} (#{context[:requester_id]}): #{details}"
end

def memory_not_found(id)
  "Error: there is no saved memory with the id #{id}."
end
