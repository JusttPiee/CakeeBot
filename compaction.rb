# Compaction: keep a channel's history small without forgetting.
#
# The history grows until it is over the high mark (MAX_HISTORY_MESSAGES / MAX_HISTORY_TOKENS).
# Then the oldest whole turns are sent to OpenAI in ONE request, which returns:
#   - a new channel summary (the old messages folded in)
#   - personality notes for the people who spoke in those messages (only if there is something new)
#   - planned events with a date that were mentioned
# The files are saved, and only then the old turns are dropped from RAM, down to the low mark
# (COMPACT_TARGET_MESSAGES / COMPACT_TARGET_TOKENS). So it runs about once every ~25 messages.
#
# If anything fails, the history is left as it is and the next reply tries again.
# (If it keeps failing, the hard ceiling in ai_channel_chat.rb cuts the history the old way.)
require 'json'
require_relative './chat_history'
require_relative './memory_store'
require_relative './memory_index'
require_relative './channel_summary'
require_relative './user_notes'
require_relative './event_notes'
require_relative './prompts'

COMPACTION_INSTRUCTIONS = read_prompt("compaction") # loaded once, at startup. {bot_name} is filled in per request.

COMPACTION_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: %w[summary events user_personalities],
  properties: {
    summary: { type: "string" },
    events: {
      type: "array",
      items: {
        type: "object", additionalProperties: false, required: %w[title when details],
        properties: { title: { type: "string" }, when: { type: "string" }, details: { type: "string" } }
      }
    },
    user_personalities: {
      type: "array",
      items: {
        type: "object", additionalProperties: false, required: %w[user_id name personality description],
        properties: { user_id: { type: "string" }, name: { type: "string" },
                      personality: { type: "string" }, description: { type: "string" } }
      }
    }
  }
}.freeze

def needs_compaction?(history)
  too_big?(history)
end

# [old_messages, kept_messages]: the oldest whole turns go to `old` until `kept` fits the low mark.
# The newest turn is always kept. The history itself is not changed.
def split_for_compaction(history)
  kept = history.dup
  while too_big?(kept, COMPACT_TARGET_MESSAGES, COMPACT_TARGET_TOKENS) && turn_count(kept) > 1
    remove_oldest_turn(kept)
  end
  [history.first(history.length - kept.length), kept]
end

# Everyone who wrote in these messages: { "123" => "Bach" }
def speakers_in(messages)
  speakers = {}
  messages.each { |message| speakers[message[:user_id]] = message[:name] if message[:role] == "user" && message[:user_id] }
  speakers
end

# Summarize the oldest turns, save the memory files, then drop those turns from the history.
# Returns true if it worked, false if not (the history is then unchanged).
def compact_history(client, history, server_id, channel_id, bot_name)
  old, _kept = split_for_compaction(history)
  return false if old.empty?

  speakers = speakers_in(old)
  current = with_server_memory_lock(server_id) { read_compaction_inputs(server_id, channel_id, speakers) }
  result = request_compaction(client, build_compaction_input(current, old, bot_name), channel_id, bot_name)
  return false if result.nil?

  with_server_memory_lock(server_id) { apply_compaction(server_id, channel_id, result, speakers, old, current) }
  history.shift(old.length)
  log "🗜️ Compacted #{old.length} old messages in channel #{channel_id} into the summary"
  true
end

# --- helpers ---

# What Cake already remembers, sent along so the AI updates it instead of starting over
def read_compaction_inputs(server_id, channel_id, speakers)
  notes = speakers.to_h do |user_id, name|
    [user_id, { name: name, personality: read_user_note(server_id, user_id)&.dig(:personality).to_s }]
  end
  { summary: read_channel_summary(server_id, channel_id), notes: notes, events: list_event_notes(server_id) }
end

# The one message sent to OpenAI: current memory + the old messages, in labelled sections
def build_compaction_input(current, old_messages, bot_name)
  summary = current[:summary][:text]
  <<~TEXT
    ## Current channel summary
    #{summary.empty? ? '(none yet)' : summary}

    ## Old messages to fold into the summary
    #{old_message_lines(old_messages, bot_name)}

    ## Current personality notes of the people in these messages
    #{personality_lines(current[:notes])}

    ## Events already saved
    #{saved_event_lines(current[:events])}
  TEXT
end

# User messages keep their "[time] Name (id): " prefix; the bot's replies get its name in front
def old_message_lines(messages, bot_name)
  format_history_for_openai(messages).map do |message|
    message[:role] == "user" ? message[:content] : "#{bot_name}: #{message[:content]}"
  end.join("\n")
end

def personality_lines(notes)
  notes.map do |user_id, note|
    personality = note[:personality].empty? ? "(no note yet)" : note[:personality]
    "#{note[:name]} (#{user_id}): #{personality}"
  end.join("\n")
end

def saved_event_lines(events)
  return "(none)" if events.empty?

  events.map { |event| "- #{event[:title]}, #{event[:when]}" }.join("\n")
end

# Ask OpenAI for the new memory. Returns the parsed result, or nil (with a log line) if anything went wrong.
def request_compaction(client, input_text, channel_id, bot_name)
  response = client.responses.create(parameters: compaction_parameters(input_text, bot_name))
  result = JSON.parse(answer_text(response))
  raise JSON::ParserError, "no summary in the answer" unless result.is_a?(Hash) && result["summary"].is_a?(String)

  result
rescue Faraday::Error => e
  log "❗ Compaction failed in channel #{channel_id}: #{describe_openai_error(e)}"
  nil
rescue JSON::ParserError => e
  log "❗ Compaction failed in channel #{channel_id}: the answer was not the expected JSON (#{e.message[0, 80]})"
  nil
end

def compaction_parameters(input_text, bot_name)
  {
    model: OPENAI_MODEL,
    instructions: COMPACTION_INSTRUCTIONS.gsub("{bot_name}", bot_name),
    input: [{ role: "user", content: input_text }],
    max_output_tokens: OPENAI_MAX_OUTPUT_TOKENS,
    reasoning: { effort: COMPACTION_REASONING_EFFORT },
    store: false, # OpenAI does not keep this conversation
    text: { format: { type: "json_schema", name: "compaction", strict: true, schema: COMPACTION_SCHEMA } }
  }
end

# Save everything the AI returned. Personality notes are only accepted for people who actually
# wrote in the old messages; events only with a valid date.
def apply_compaction(server_id, channel_id, result, speakers, old, current)
  last_id = last_message_id(old) || current[:summary][:last_message_id]
  write_channel_summary(server_id, channel_id, result["summary"], last_id)
  save_personalities(server_id, result["user_personalities"].to_a, speakers)
  save_events(server_id, result["events"].to_a)
  rebuild_memory_index(server_id)
end

def save_personalities(server_id, personalities, speakers)
  personalities.each do |item|
    user_id = item["user_id"].to_s
    next unless speakers.key?(user_id) # never write about someone who wasn't in these messages

    write_user_personality(server_id, user_id, speakers[user_id], item["personality"], item["description"])
  end
end

def save_events(server_id, events)
  events.each do |event|
    saved = save_event_note(server_id, event["title"].to_s, event["when"].to_s, event["details"].to_s)
    log "⚠️ Compaction skipped event '#{event['title']}': bad date '#{event['when']}'" if saved.nil?
  end
end
