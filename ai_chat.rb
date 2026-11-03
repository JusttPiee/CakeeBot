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

# The system prompt goes first and is never stored in the history, so trimming can't remove it
def build_messages(history, bot_name)
  [{ role: "system", content: build_system_prompt(bot_name) }] + format_history_for_openai(history)
end

# Returns the AI's answer, or nil if the request failed.
# If the model used the whole budget on thinking and the answer is empty, try once more without thinking.
def ask_ai(client, history, bot_name)
  answer = request_answer(client, history, bot_name, OPENAI_REASONING_EFFORT)
  return answer if answer.nil? || !answer.strip.empty? # an API error, or a real answer

  log "↻ Retrying with reasoning '#{OPENAI_FALLBACK_REASONING_EFFORT}'"
  request_answer(client, history, bot_name, OPENAI_FALLBACK_REASONING_EFFORT)
end

# Get one answer from OpenAI, letting the AI use tools on the way.
# Returns the answer text ("" if empty), or nil if the request failed.
#
# Each round: ask OpenAI. If it answers, we are done. If it asks for tools instead,
# run them, add the results to the conversation, and ask again.
# The tool steps only live in `messages` here; the saved history keeps just the question and the final answer.
def request_answer(client, history, bot_name, reasoning_effort)
  messages = build_messages(history, bot_name)

  MAX_TOOL_ROUNDS.times do
    response = send_chat_request(client, messages, reasoning_effort, tools_allowed: true)
    message = response.dig("choices", 0, "message") || {}
    tool_calls = message["tool_calls"].to_a
    return answer_text(response) if tool_calls.empty?

    messages << { role: "assistant", content: message["content"], tool_calls: tool_calls }
    messages.concat(run_tool_calls(tool_calls))
  end

  log "⚠️ Used all #{MAX_TOOL_ROUNDS} tool rounds, asking for an answer without more tools"
  answer_text(send_chat_request(client, messages, reasoning_effort, tools_allowed: false))
rescue Faraday::Error => e
  log "❗ OpenAI request failed: #{describe_openai_error(e)}" # no headers, so the API key never reaches the terminal
  nil
end

# One request to OpenAI. tools_allowed: false means "you must answer now, no more tools".
def send_chat_request(client, messages, reasoning_effort, tools_allowed:)
  parameters = {
    model: OPENAI_MODEL,
    messages: messages,
    max_completion_tokens: OPENAI_MAX_COMPLETION_TOKENS, # thinking + reply together
    reasoning_effort: reasoning_effort
  }
  parameters[:temperature] = OPENAI_TEMPERATURE if OPENAI_TEMPERATURE # some models only accept the default
  add_tools(parameters, tools_allowed)
  client.chat(parameters: parameters)
end

# Tell OpenAI which tools exist. The list is still sent when tools are not allowed,
# because the conversation may already contain tool results.
def add_tools(parameters, tools_allowed)
  definitions = tool_definitions
  return if definitions.empty?

  parameters[:tools] = definitions
  parameters[:tool_choice] = "none" unless tools_allowed
end

# The reply text from a response ("" if empty, and then the reason is logged)
def answer_text(response)
  answer = response.dig("choices", 0, "message", "content").to_s
  log_empty_answer(response) if answer.strip.empty?
  answer
end

# OpenAI can "succeed" but return no text, e.g. when the model used every token on thinking.
# Log why, so this never fails silently.
def log_empty_answer(response)
  finish_reason = response.dig("choices", 0, "finish_reason")
  used = response.dig("usage", "completion_tokens")
  reasoning = response.dig("usage", "completion_tokens_details", "reasoning_tokens")
  log "❗ OpenAI returned an empty answer (finish_reason: #{finish_reason}, tokens used: #{used}, of which reasoning: #{reasoning})"
end

# Every chunk replies to the user's message, without pinging them
def send_reply(event, answer)
  split_message(answer).each { |chunk| event.message.reply!(chunk, mention_user: false) }
end
