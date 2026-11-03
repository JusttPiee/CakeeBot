# Every tool the AI can use. To add a tool (e.g. mute or ban later):
#   1. create tools/<name>.rb with a definition and a run_<name>(arguments) method
#   2. add it to available_tools below
require 'json'
require_relative './tools/web_search'
require_relative './tools/read_webpage'

# name => { definition: what the AI sees, run: the Ruby method that does the work }
def available_tools
  tools = {}
  tools["web_search"] = { definition: WEB_SEARCH_DEFINITION, run: method(:run_web_search) } if web_search_enabled?
  tools["read_webpage"] = { definition: READ_WEBPAGE_DEFINITION, run: method(:run_read_webpage) }
  tools
end

# The list sent to OpenAI with every request
def tool_definitions
  available_tools.values.map { |tool| tool[:definition] }
end

# Runs one tool the AI asked for. Always returns text, even when something goes wrong,
# so the AI can still answer and the bot never crashes because of a tool.
def run_tool(name, arguments_json)
  tool = available_tools[name]
  return "Error: there is no tool called #{name}." if tool.nil?

  arguments = JSON.parse(arguments_json.to_s.empty? ? '{}' : arguments_json)
  tool[:run].call(arguments)
rescue JSON::ParserError
  "Error: the tool arguments were not valid JSON."
rescue StandardError => e
  log "⚠️ Tool #{name} failed (#{e.class})"
  "Error: the #{name} tool failed (#{e.class}). Answer without it."
end

# OpenAI can ask for several tools at once. Each result is sent back as a "tool" message
# with the same id, so OpenAI knows which result belongs to which request.
def run_tool_calls(tool_calls)
  tool_calls.map do |call|
    result = run_tool(call.dig("function", "name"), call.dig("function", "arguments"))
    { role: "tool", tool_call_id: call["id"], content: result }
  end
end
