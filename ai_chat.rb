# Talking to OpenAI and sending the reply back to Discord.
# Settings come from config.rb; log and describe_openai_error come from cakee.rb.
require 'date'
require_relative './recent_activity' # "Recently, in other channels" in the prompt
require_relative './prompts'
require_relative './chat_history'
require_relative './message_splitter'
require_relative './tool_list'
require_relative './memory_index'
require_relative './channel_summary'
require_relative './memory_questions'

# The bot's personality: who it is and how it talks. Edit prompts/personality.txt to change it, no code needed.
# {bot_name} is replaced with the bot's name in the server. Changes apply on the next message, no restart.
# The file is local to each bot (git ignored). If it is missing, it is created from personality.default.txt.
PERSONALITY_FILE = File.join(PROMPTS_DIR, 'personality.txt')

# Shared by every bot and kept out of the personality, so editing it can't break them
# and new commands reach every bot. Loaded once, at startup.
CAPABILITIES = read_prompt("capabilities")
CHAT_RULES = read_prompt("chat_rules")
MEMORY_RULES = read_prompt("memory_rules")

def default_personality
  read_prompt("personality.default")
end

# Creates the personality file from the template. An existing file is never touched.
def ensure_personality_file(path = PERSONALITY_FILE)
  File.write(path, default_personality) unless File.exist?(path)
end

def load_personality(path = PERSONALITY_FILE)
  ensure_personality_file(path)
  text = File.read(path).strip
  text.empty? ? default_personality : text
end

# Final system prompt = personality (with the bot's name filled in) + capabilities + technical rules + memory rules + today's date,
# then the server's memory index, this channel's summary and any open memory question (when there are any).
# The parts that change least come first, so OpenAI can cache the start of the prompt.
def build_system_prompt(bot_name, memory_index: "", channel_summary: "", recent_activity: "", open_question: "")
  personality = load_personality.gsub("{bot_name}", bot_name)
  prompt = "#{personality}\n\n#{CAPABILITIES}\n\n#{CHAT_RULES}\n\n#{MEMORY_RULES}\n\nToday's date is #{Date.today.strftime('%A, %d %B %Y')}."
  prompt += "\n\n## Long-term memory (index of saved notes)\n#{memory_index}" unless memory_index.empty?
  prompt += "\n\n## Summary of earlier conversation in this channel\n#{channel_summary}" unless channel_summary.empty?
  prompt += "\n\n## Recently, in other channels (background only)\n#{recent_activity}" unless recent_activity.empty?
  prompt += "\n\n#{open_question}" unless open_question.empty?
  prompt
end

# Memory for the prompt: the server's index (everywhere) and the channel summary (AI channels only).
# context comes from Discord: { server_id:, channel_id:, ... }. No server (e.g. tests, DMs) = no memory.
def load_prompt_memory(context)
  memory = { memory_index: "", channel_summary: "" }
  server_id = context[:server_id]
  return memory if server_id.nil?

  index = with_server_memory_lock(server_id) { rebuild_memory_index(server_id) }
  memory[:memory_index] = cap_for_prompt(index, "Memory index")
  if context[:channel_id]
    summary = read_channel_summary(server_id, context[:channel_id])[:text]
    memory[:channel_summary] = cap_for_prompt(summary, "Channel summary")
  end
  memory[:recent_activity] = recent_activity_for_prompt(server_id, context)
  memory[:open_question] = open_question_prompt(server_id, context[:requester_id])
  memory
end

# What happened around Cake lately in OTHER channels (recent_activity.rb). A mention has no channel_id,
# so the channel the reply is for comes from the channel object. A failure only costs this part of the prompt.
def recent_activity_for_prompt(server_id, context)
  channel_id = context[:channel_id] || context[:channel]&.id
  recent_activity_text(recent_entries_for(server_id, channel_id))
rescue StandardError => e
  log "⚠️ Could not read the recent activity (#{e.class})"
  ""
end

# Temporary guard until size limits are designed: never put more than MEMORY_PROMPT_MAX_CHARS into the prompt
def cap_for_prompt(text, label)
  return text if text.length <= MEMORY_PROMPT_MAX_CHARS

  log "⚠️ #{label} is longer than #{MEMORY_PROMPT_MAX_CHARS} characters, cut for the prompt"
  text[0, MEMORY_PROMPT_MAX_CHARS]
end

# Returns the AI's answer, or nil if the request failed.
# context: facts from Discord for memory and tools { server_id:, channel_id:, requester_id:, requester_name: }
# If the model used the whole budget on thinking and the answer is empty, try once more without thinking.
def ask_ai(client, history, bot_name, context = {})
  context = context.merge(client: client, images: images_in_history(history), pending_images: [], image_looks: 0,
                          text_files: text_files_in_history(history), text_file_reads: 0, channel_searches: 0)
  memory = load_prompt_memory(context)
  answer = request_answer(client, history, bot_name, OPENAI_REASONING_EFFORT, memory, context)
  return answer if answer.nil? || !answer.strip.empty? # an API error, or a real answer

  log "↻ Retrying with reasoning '#{OPENAI_FALLBACK_REASONING_EFFORT}'"
  request_answer(client, history, bot_name, OPENAI_FALLBACK_REASONING_EFFORT, memory, context)
end

# Get one answer from OpenAI (Responses API), letting the AI use tools on the way.
# Returns the answer text ("" if empty), or nil if the request failed.
#
# Each round: ask OpenAI. If it answers, we are done. If it asks for tools instead,
# run them, add everything it gave us (its thinking + tool requests) and the tool results
# to `input`, and ask again. The thinking must go back too, or the AI loses track of its plan.
# The tool steps only live in `input` here; the saved history keeps just the question and the final answer.
def request_answer(client, history, bot_name, reasoning_effort, memory = {}, context = {})
  instructions = build_system_prompt(bot_name, **memory)
  input = format_history_for_openai(history)

  MAX_TOOL_ROUNDS.times do
    response = send_ai_request(client, instructions, input, reasoning_effort, tools_allowed: true)
    tool_calls = output_items(response, "function_call")
    return answer_text(response) if tool_calls.empty?

    input.concat(response["output"].to_a) # thinking (locked) + tool requests, sent back as they came
    input.concat(run_tool_calls(tool_calls, context))
    input.concat(take_pending_images(context)) # pictures opened with look_at_image
  end

  log "⚠️ Used all #{MAX_TOOL_ROUNDS} tool rounds, asking for an answer without more tools"
  answer_text(send_ai_request(client, instructions, input, reasoning_effort, tools_allowed: false))
rescue Faraday::Error => e
  log "❗ OpenAI request failed: #{describe_openai_error(e)}" # no headers, so the API key never reaches the terminal
  nil
end

# One request to OpenAI. tools_allowed: false means "you must answer now, no more tools".
# store: false = OpenAI does not save this conversation. Because of that, it hands us its thinking
# in a locked (encrypted) form, so we can send it back in the next round.
def send_ai_request(client, instructions, input, reasoning_effort, tools_allowed:)
  parameters = {
    model: OPENAI_MODEL,
    instructions: instructions, # the system prompt, never stored in the history, so trimming can't remove it
    input: input,
    max_output_tokens: OPENAI_MAX_OUTPUT_TOKENS, # thinking + reply together
    reasoning: { effort: reasoning_effort },
    store: false,
    include: ["reasoning.encrypted_content"]
  }
  parameters[:temperature] = OPENAI_TEMPERATURE if OPENAI_TEMPERATURE # some models only accept the default
  add_tools(parameters, tools_allowed)
  client.responses.create(parameters: parameters)
end

# The response is a list of items: "reasoning" (thinking), "function_call" (tool request), "message" (reply)
def output_items(response, type)
  response["output"].to_a.select { |item| item["type"] == type }
end

# Tell OpenAI which tools exist. The list is still sent when tools are not allowed,
# because the conversation may already contain tool results.
def add_tools(parameters, tools_allowed)
  definitions = tool_definitions
  return if definitions.empty?

  parameters[:tools] = definitions
  parameters[:tool_choice] = "none" unless tools_allowed
end

# The reply text from a response ("" if empty, and then the reason is logged).
# A "message" item holds a list of parts; the text parts are joined together.
def answer_text(response)
  answer = output_items(response, "message").map do |message|
    message["content"].to_a.map { |part| part["text"].to_s }.join
  end.join
  log_empty_answer(response) if answer.strip.empty?
  answer
end

# OpenAI can "succeed" but return no text, e.g. when the model used every token on thinking
# (then status is "incomplete" and the reason is "max_output_tokens"). Log why, so this never fails silently.
def log_empty_answer(response)
  status = response["status"]
  reason = response.dig("incomplete_details", "reason")
  used = response.dig("usage", "output_tokens")
  reasoning = response.dig("usage", "output_tokens_details", "reasoning_tokens")
  log "❗ OpenAI returned an empty answer (status: #{status}, reason: #{reason}, tokens used: #{used}, of which reasoning: #{reasoning})"
end

# Every chunk replies to the user's message, without pinging them.
# Returns the last message sent (its id is saved in the history), or nil if nothing was sent.
def send_reply(event, answer)
  sent = nil
  split_message(answer).each { |chunk| sent = event.message.reply!(chunk, mention_user: false) }
  sent
end
