# Tool: replace several overlapping memories with one, so notes stay short. All or nothing:
# if any memory can't be merged, nothing changes. Only whoever saved them can merge them
# (checked here, using who is asking from Discord), so the AI can't tidy someone else's note.
require_relative '../memory_store'
require_relative '../memory_items'
require_relative '../memory_index'
require_relative './remember_about_me'
require_relative './update_memory'

MERGE_MEMORIES_DEFINITION = {
  type: "function",
  name: "merge_memories",
  description: "Replace several overlapping or repeated memories with one, using their ids in square brackets " \
               "from the memory list. Use it when the sender asks you to clean up or combine their memories. " \
               "Keep every detail that is still true; when memories contradict each other, keep the newest. " \
               "It only works on what the sender saved themselves.",
  parameters: {
    type: "object",
    properties: {
      memory_ids: { type: "array", items: { type: "string" }, description: "The ids to merge, without the brackets" },
      new_text: { type: "string", description: "The one memory that replaces them, short, without why and how" },
      **MEMORY_WHY_AND_HOW_PARAMETERS
    },
    required: %w[memory_ids new_text]
  }
}.freeze

def run_merge_memories(arguments, context)
  return MEMORY_NOT_AVAILABLE if context[:server_id].nil?

  ids = arguments["memory_ids"].to_a.map { |id| id.to_s.strip }.uniq
  return "Error: merging needs at least two different memory ids." if ids.length < 2

  new_text = text_with_why_and_how(arguments["new_text"], arguments)
  problem = check_fact(new_text)
  return problem if problem

  with_server_memory_lock(context[:server_id]) { merge_memories_locked(ids, new_text, context) }
end

def merge_memories_locked(ids, new_text, context)
  server_id = context[:server_id]
  items = ids.map { |id| find_memory_item(server_id, id) }
  missing = ids[items.index(nil)] if items.include?(nil)
  return memory_not_found(missing) if missing

  problem = check_merge_allowed(items, context[:requester_id])
  return problem if problem

  log "🧠 merge_memories by #{context[:requester_name]} (#{context[:requester_id]}): #{items.length} memories => #{new_text}"
  merge_memory_items(server_id, items, new_text)
  rebuild_memory_index(server_id)
  "Merged #{items.length} memories into one."
end

# An error message for the AI, or nil if these memories can be merged
def check_merge_allowed(items, requester_id)
  return "Error: only the person who saved these memories can merge them." unless items.all? { |item| can_change_memory?(item, requester_id) }
  return "Error: personal memories and notes about other people can't be merged together." if items.map { |item| item[:kind] }.uniq.length > 1
  return "Error: notes about different people can't be merged." if items.map { |item| item[:subject_id] }.uniq.length > 1

  nil
end
