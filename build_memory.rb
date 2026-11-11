# !buildmemory (admins only): build a personality note for each person from their old messages.
# Normal compaction only learns from messages sent while AI mode is on. This reads back through
# every text channel the bot can see, so Cake knows people from day one.
#
#   1. read the last BUILD_MEMORY_MESSAGES_PER_CHANNEL messages of every text channel
#   2. group them by person (bots are left out)
#   3. skip people with too few messages, and people who turned personality notes off (or used !forgetme)
#   4. one OpenAI request per person, most active first, with ONLY that person's own messages
#   5. check the new note with moderation, then save it (the same Personality section compaction writes)
#
# It runs in the background, so the bot keeps answering while it works. One build per server at a time.
# Saved facts ("Asked to remember") are never touched.
require 'json'
require_relative './config'
require_relative './prompts'
require_relative './discord_history'
require_relative './memory_store'
require_relative './memory_index'
require_relative './user_notes'
require_relative './moderation'
require_relative './ai_chat' # answer_text

BUILD_MEMORY_INSTRUCTIONS = read_prompt("build_memory") # loaded once, at startup. {bot_name} is filled in per request.
BUILD_MEMORY_LINE_MAX_CHARS = 500 # one very long message can't take a person's whole budget

BUILD_MEMORY_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: %w[personality description],
  properties: { personality: { type: "string" }, description: { type: "string" } }
}.freeze

# Read, plan and build. channels: ReadingChannels (see discord_history.rb).
# Returns a report hash for build_memory_report_text.
def build_server_memory(client, server_id, channels, bot_name)
  read = read_channels_messages(channels)
  plan = plan_memory_build(server_id, messages_by_person(read[:messages]))
  results = Hash.new(0)
  plan[:chosen].each do |user_id, person|
    results[build_person_note_safely(client, server_id, user_id, person, bot_name)] += 1
  end
  with_server_memory_lock(server_id) { rebuild_memory_index(server_id) }
  { read: read, plan: plan, results: results }
end

# --- step 1: read ---

# Every text channel of the server, ready to read as raw JSON (see discord_history.rb for why)
def server_reading_channels(server, bot)
  server.text_channels.map { |channel| ReadingChannel.new(channel, bot) }
end

# { messages: [...], channels_read:, channels_skipped: }. A channel the bot can't read is skipped.
def read_channels_messages(channels)
  report = { messages: [], channels_read: 0, channels_skipped: 0 }
  channels.each do |channel|
    report[:messages].concat(plain_messages(channel, fetch_older_messages(channel, BUILD_MEMORY_MESSAGES_PER_CHANNEL)))
    report[:channels_read] += 1
  rescue StandardError => e
    report[:channels_skipped] += 1
    log "⚠️ !buildmemory could not read ##{channel.name} (#{e.class}), skipped it"
  end
  report
end

# --- step 2 and 3: group and choose ---

# { "123" => { name:, messages: [...] } }. Bots are left out. The name is from their newest message.
def messages_by_person(messages)
  people = {}
  messages.sort_by { |message| message[:time] }.each do |message|
    next if message[:bot]

    person = people[message[:author_id]] ||= { name: "", messages: [] }
    person[:name] = message[:author_name]
    person[:messages] << message
  end
  people
end

# { chosen: [[user_id, person], ...] most active first, too_few:, turned_off:, over_limit: }
def plan_memory_build(server_id, people)
  plan = { chosen: [], too_few: 0, turned_off: 0, over_limit: 0 }
  people.each do |user_id, person|
    if person[:messages].length < BUILD_MEMORY_MIN_MESSAGES
      plan[:too_few] += 1
    elsif personality_turned_off?(server_id, user_id)
      plan[:turned_off] += 1
    else
      plan[:chosen] << [user_id, person]
    end
  end
  limit_people_to_build(plan)
end

def limit_people_to_build(plan)
  by_activity = plan[:chosen].sort_by { |_user_id, person| -person[:messages].length }
  plan[:chosen] = by_activity.first(BUILD_MEMORY_MAX_PEOPLE)
  plan[:over_limit] = by_activity.length - plan[:chosen].length
  plan
end

# They removed their personality note (forget_my_personality) or used !forgetme
def personality_turned_off?(server_id, user_id)
  note = with_server_memory_lock(server_id) { read_user_note(server_id, user_id) }
  note ? note[:personality_off] : false
end

# --- step 4 and 5: one person ---

# A failure (OpenAI down, bad JSON) only skips this person, the build goes on
def build_person_note_safely(client, server_id, user_id, person, bot_name)
  build_person_note(client, server_id, user_id, person, bot_name)
rescue StandardError => e
  log "⚠️ !buildmemory failed for user #{user_id} (#{e.class})"
  :failed
end

# :built, :nothing (their messages showed nothing about them) or :refused (moderation)
def build_person_note(client, server_id, user_id, person, bot_name)
  note = with_server_memory_lock(server_id) { read_user_note(server_id, user_id) }
  current = note ? note[:personality] : ""
  result = request_person_note(client, build_memory_input(user_id, person, current), bot_name)
  personality = result["personality"].to_s.strip
  return :nothing if personality.empty?
  return refuse_person_note(user_id) if moderation_flags(client, "#{personality}\n#{result['description']}").to_a.any?

  # write_user_personality still does nothing if they turned it off while the build was running
  with_server_memory_lock(server_id) { write_user_personality(server_id, user_id, person[:name], personality, result["description"].to_s) }
  :built
end

def refuse_person_note(user_id)
  log "🛡️ !buildmemory: the personality note for user #{user_id} was refused by moderation, not saved"
  :refused
end

def build_memory_input(user_id, person, current_personality)
  <<~TEXT
    ## The person
    #{person[:name]} (#{user_id})

    ## Current personality note
    #{current_personality.empty? ? '(none yet)' : current_personality}

    ## Their messages (oldest first)
    #{person_message_lines(person)}
  TEXT
end

# Their newest messages that fit in BUILD_MEMORY_MAX_CHARS_PER_PERSON, oldest first
def person_message_lines(person)
  lines = []
  total = 0
  person[:messages].reverse_each do |message| # newest first, so the newest are kept
    line = plain_message_line(message, BUILD_MEMORY_LINE_MAX_CHARS)
    break if total + line.length > BUILD_MEMORY_MAX_CHARS_PER_PERSON

    lines << line
    total += line.length + 1
  end
  lines.reverse.join("\n")
end

# The parsed JSON answer. Raises on API errors or a broken answer.
def request_person_note(client, input_text, bot_name)
  response = client.responses.create(parameters: build_memory_parameters(input_text, bot_name))
  result = JSON.parse(answer_text(response))
  raise JSON::ParserError, "no personality in the answer" unless result.is_a?(Hash) && result.key?("personality")

  result
end

def build_memory_parameters(input_text, bot_name)
  {
    model: OPENAI_MODEL,
    instructions: BUILD_MEMORY_INSTRUCTIONS.gsub("{bot_name}", bot_name),
    input: [{ role: "user", content: input_text }],
    max_output_tokens: OPENAI_MAX_OUTPUT_TOKENS,
    reasoning: { effort: BUILD_MEMORY_REASONING_EFFORT },
    store: false, # OpenAI does not keep these messages
    text: { format: { type: "json_schema", name: "personality_note", strict: true, schema: BUILD_MEMORY_SCHEMA } }
  }
end

# --- the Discord command ---

BUILD_MEMORY_RUNNING = {} # server_id => true while a build runs there
BUILD_MEMORY_RUNNING_LOCK = Mutex.new

# true if no build was running in this server (and marks it as running now)
def start_memory_build?(server_id)
  BUILD_MEMORY_RUNNING_LOCK.synchronize do
    next false if BUILD_MEMORY_RUNNING[server_id.to_s]

    BUILD_MEMORY_RUNNING[server_id.to_s] = true
  end
end

def memory_build_running?(server_id)
  BUILD_MEMORY_RUNNING_LOCK.synchronize { BUILD_MEMORY_RUNNING.key?(server_id.to_s) }
end

def finish_memory_build(server_id)
  BUILD_MEMORY_RUNNING_LOCK.synchronize { BUILD_MEMORY_RUNNING.delete(server_id.to_s) }
end

# Checks who may run it, then builds in the background. Returns the thread, or nil if it didn't start.
# channels is only given by tests; normally it is every text channel of the server.
def build_memory_command(event, client, channels = nil)
  problem = build_memory_problem(event)
  if problem
    event.respond(problem)
    return nil
  end

  event.respond("🧠 Reading old messages in every channel I can see, this can take a few minutes...")
  log "🧠 !buildmemory started by #{event.author.display_name} (#{event.author.id}) in #{event.server.name}"
  bot_name = event.server.bot.display_name
  channels ||= server_reading_channels(event.server, event.bot)
  Thread.new { run_memory_build(event, client, channels, bot_name) }
end

# Why the build can't start (text for Discord), or nil if it can. The last check also marks it as running.
# The admin check is done here in code: a message or memory note can never give this permission.
def build_memory_problem(event)
  return "❗ `!buildmemory` only works in a server." if event.server.nil?
  return "⛔ Only admins can use `!buildmemory`." unless event.user.permission?(:administrator)
  return "⏳ I'm already building memory for this server, please wait." unless start_memory_build?(event.server.id)

  nil
end

def run_memory_build(event, client, channels, bot_name)
  event.respond(memory_build_result_text(client, event.server.id, event.server.name, channels, bot_name))
rescue StandardError => e
  log "❗ !buildmemory could not post its report in #{event.server.name} (#{e.class})"
ensure
  finish_memory_build(event.server.id)
end

# Runs the whole build and returns what to tell whoever started it: the report, or one line if it failed.
# It never raises, and it does not mark the build as finished: the caller does that (finish_memory_build).
# Used by the Discord command above and by the web UI (web_api/routes/action_routes.rb).
def memory_build_result_text(client, server_id, server_name, channels, bot_name)
  report = build_server_memory(client, server_id, channels, bot_name)
  log "🧠 !buildmemory finished in #{server_name}: #{report[:results].to_h.inspect}"
  build_memory_report_text(report)
rescue StandardError => e
  log "❗ !buildmemory failed in #{server_name} (#{e.class})"
  "❗ Building memory failed, please try again later."
end

def build_memory_report_text(report)
  read = report[:read]
  plan = report[:plan]
  results = report[:results]
  lines = ["✅ Read #{read[:messages].length} messages in #{read[:channels_read]} channels and built #{results[:built]} personality notes."]
  lines << "- couldn't read #{read[:channels_skipped]} channels (no permission)" if read[:channels_skipped].positive?
  lines << "- skipped #{plan[:too_few]} people with fewer than #{BUILD_MEMORY_MIN_MESSAGES} messages" if plan[:too_few].positive?
  lines << "- skipped #{plan[:turned_off]} people who turned their personality note off" if plan[:turned_off].positive?
  lines << "- skipped #{plan[:over_limit]} less active people (limit: #{BUILD_MEMORY_MAX_PEOPLE})" if plan[:over_limit].positive?
  lines << "- nothing to note for #{results[:nothing]} people" if results[:nothing].positive?
  lines << "- #{results[:refused]} notes were not saved because they looked harmful" if results[:refused].positive?
  lines << "- #{results[:failed]} people failed (AI error), run it again later to retry" if results[:failed].positive?
  lines.join("\n")
end
