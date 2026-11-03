# Talking to OpenAI and sending the reply back to Discord.
# Settings come from config.rb; log and describe_openai_error come from cakee.rb.
require 'date'
require_relative './chat_history'
require_relative './message_splitter'
require_relative './tool_list'

# The bot's personality: who it is and what it can do. Edit the text file to change it, no code needed.
# {bot_name} is replaced with the bot's name in the server. Changes apply on the next message, no restart.
PERSONALITY_FILE = File.join(__dir__, 'prompts', 'personality.txt')
DEFAULT_PERSONALITY = "You are {bot_name}, a friendly Discord bot." # used if the file is missing or empty

# Technical rules the code depends on (the message prefix). Kept here so editing the personality can't break them.
CHAT_RULES = <<~RULES
  Each user message starts with "Nickname (user_id): " so you know who is speaking.
  Several people may talk in the same channel. Do not start your replies with this prefix.
  Only use tools when you need them. Search only for current or changing information, not for things you already know.
  When you use information from the web, mention where it came from.
RULES

def load_personality(path = PERSONALITY_FILE)
  text = File.exist?(path) ? File.read(path).strip : ""
  text.empty? ? DEFAULT_PERSONALITY : text
end

# Final system prompt = personality (with the bot's name filled in) + technical rules + today's date
def build_system_prompt(bot_name)
  personality = load_personality.gsub("{bot_name}", bot_name)
  "#{personality}\n\n#{CHAT_RULES}\nToday's date is #{Date.today.strftime('%A, %d %B %Y')}."
end

# Returns the AI's answer, or nil if the request failed.
# If the model used the whole budget on thinking and the answer is empty, try once more without thinking.
def ask_ai(client, history, bot_name)
  answer = request_answer(client, history, bot_name, OPENAI_REASONING_EFFORT)
  return answer if answer.nil? || !answer.strip.empty? # an API error, or a real answer

  log "↻ Retrying with reasoning '#{OPENAI_FALLBACK_REASONING_EFFORT}'"
  request_answer(client, history, bot_name, OPENAI_FALLBACK_REASONING_EFFORT)
end

# Get one answer from OpenAI (Responses API), letting the AI use tools on the way.
# Returns the answer text ("" if empty), or nil if the request failed.
#
# Each round: ask OpenAI. If it answers, we are done. If it asks for tools instead,
# run them, add everything it gave us (its thinking + tool requests) and the tool results
# to `input`, and ask again. The thinking must go back too, or the AI loses track of its plan.
# The tool steps only live in `input` here; the saved history keeps just the question and the final answer.
def request_answer(client, history, bot_name, reasoning_effort)
  instructions = build_system_prompt(bot_name)
  input = format_history_for_openai(history)

  MAX_TOOL_ROUNDS.times do
    response = send_ai_request(client, instructions, input, reasoning_effort, tools_allowed: true)
    tool_calls = output_items(response, "function_call")
    return answer_text(response) if tool_calls.empty?

    input.concat(response["output"].to_a) # thinking (locked) + tool requests, sent back as they came
    input.concat(run_tool_calls(tool_calls))
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

# Every chunk replies to the user's message, without pinging them
def send_reply(event, answer)
  split_message(answer).each { |chunk| event.message.reply!(chunk, mention_user: false) }
end
