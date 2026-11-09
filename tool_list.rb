# Every tool the AI can use. To add a tool (e.g. mute or ban later):
#   1. create tools/<name>.rb with a definition and a run_<name>(arguments, context) method
#   2. add it to available_tools below
require 'json'
require_relative './tools/web_search'
require_relative './tools/read_webpage'
require_relative './tools/read_memory'
require_relative './tools/save_event'
require_relative './tools/remember_about_me'
require_relative './tools/look_at_image'
require_relative './tools/read_text_file'
require_relative './tools/remember_about_someone'
require_relative './tools/update_memory'
require_relative './tools/forget_memory'
require_relative './tools/merge_memories'
require_relative './tools/update_my_personality'
require_relative './tools/forget_my_personality'

# name => { definition: what the AI sees, run: the Ruby method that does the work }
def available_tools
  tools = {}
  tools["web_search"] = { definition: WEB_SEARCH_DEFINITION, run: method(:run_web_search) } if web_search_enabled?
  tools["read_webpage"] = { definition: READ_WEBPAGE_DEFINITION, run: method(:run_read_webpage) }
  tools["read_memory"] = { definition: READ_MEMORY_DEFINITION, run: method(:run_read_memory) }
  tools["save_event"] = { definition: SAVE_EVENT_DEFINITION, run: method(:run_save_event) }
  tools["remember_about_me"] = { definition: REMEMBER_ABOUT_ME_DEFINITION, run: method(:run_remember_about_me) }
  tools["look_at_image"] = { definition: LOOK_AT_IMAGE_DEFINITION, run: method(:run_look_at_image) }
  tools["read_text_file"] = { definition: READ_TEXT_FILE_DEFINITION, run: method(:run_read_text_file) }
  tools["remember_about_someone"] = { definition: REMEMBER_ABOUT_SOMEONE_DEFINITION, run: method(:run_remember_about_someone) }
  tools["update_memory"] = { definition: UPDATE_MEMORY_DEFINITION, run: method(:run_update_memory) }
  tools["forget_memory"] = { definition: FORGET_MEMORY_DEFINITION, run: method(:run_forget_memory) }
  tools["merge_memories"] = { definition: MERGE_MEMORIES_DEFINITION, run: method(:run_merge_memories) }
  tools["update_my_personality"] = { definition: UPDATE_MY_PERSONALITY_DEFINITION, run: method(:run_update_my_personality) }
  tools["forget_my_personality"] = { definition: FORGET_MY_PERSONALITY_DEFINITION, run: method(:run_forget_my_personality) }
  tools
end

# The list sent to OpenAI with every request
def tool_definitions
  available_tools.values.map { |tool| tool[:definition] }
end

# Runs one tool the AI asked for. Always returns text, even when something goes wrong,
# so the AI can still answer and the bot never crashes because of a tool.
# context = facts from Discord, never from the AI: { server_id:, channel_id:, requester_id:, requester_name: },
# plus the OpenAI client (for moderation)
def run_tool(name, arguments_json, context = {})
  tool = available_tools[name]
  return "Error: there is no tool called #{name}." if tool.nil?

  arguments = JSON.parse(arguments_json.to_s.empty? ? '{}' : arguments_json)
  tool[:run].call(arguments, context)
rescue JSON::ParserError
  "Error: the tool arguments were not valid JSON."
rescue StandardError => e
  log "⚠️ Tool #{name} failed (#{e.class})"
  "Error: the #{name} tool failed (#{e.class}). Answer without it."
end

# OpenAI can ask for several tools at once. Each result is sent back as a "function_call_output"
# with the same call_id, so OpenAI knows which result belongs to which request.
def run_tool_calls(tool_calls, context = {})
  tool_calls.map do |call|
    result = run_tool(call["name"], call["arguments"], context)
    { type: "function_call_output", call_id: call["call_id"], output: result }
  end
end
