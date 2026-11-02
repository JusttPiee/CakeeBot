# Talking to OpenAI and sending the reply back to Discord.
# Settings come from config.rb; log and describe_openai_error come from cakee.rb.
require_relative './chat_history'
require_relative './message_splitter'

# The bot's personality: who it is and what it can do. Edit the text file to change it, no code needed.
# {bot_name} is replaced with the bot's name in the server. Changes apply on the next message, no restart.
PERSONALITY_FILE = File.join(__dir__, 'prompts', 'personality.txt')
DEFAULT_PERSONALITY = "You are {bot_name}, a friendly Discord bot." # used if the file is missing or empty

# Technical rules the code depends on (the message prefix). Kept here so editing the personality can't break them.
CHAT_RULES = <<~RULES
  Each user message starts with "Nickname (user_id): " so you know who is speaking.
  Several people may talk in the same channel. Do not start your replies with this prefix.
RULES

def load_personality(path = PERSONALITY_FILE)
  text = File.exist?(path) ? File.read(path).strip : ""
  text.empty? ? DEFAULT_PERSONALITY : text
end

# Final system prompt = personality (with the bot's name filled in) + technical rules
def build_system_prompt(bot_name)
  personality = load_personality.gsub("{bot_name}", bot_name)
  "#{personality}\n\n#{CHAT_RULES}"
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

# One OpenAI request. Returns the answer text ("" if empty), or nil if the request failed.
def request_answer(client, history, bot_name, reasoning_effort)
  parameters = {
    model: OPENAI_MODEL,
    messages: build_messages(history, bot_name),
    max_completion_tokens: OPENAI_MAX_COMPLETION_TOKENS, # thinking + reply together
    reasoning_effort: reasoning_effort
  }
  parameters[:temperature] = OPENAI_TEMPERATURE if OPENAI_TEMPERATURE # some models only accept the default

  response = client.chat(parameters: parameters)
  answer = response.dig("choices", 0, "message", "content").to_s
  log_empty_answer(response) if answer.strip.empty?
  answer
rescue Faraday::Error => e
  log "❗ OpenAI request failed: #{describe_openai_error(e)}" # no headers, so the API key never reaches the terminal
  nil
end

# OpenAI can "succeed" but return no text, e.g. when the model used every token on thinking.
# Log why, so this never fails silently.
def log_empty_answer(response)
  finish_reason = response.dig("choices", 0, "finish_reason")
  used = response.dig("usage", "completion_tokens")
  reasoning = response.dig("usage", "completion_tokens_details", "reasoning_tokens")
  log "❗ OpenAI returned an empty answer (finish_reason: #{finish_reason}, tokens used: #{used}, of which reasoning: #{reasoning})"
end

def send_reply(event, answer)
  split_message(answer).each { |chunk| event.respond(chunk) }
end
