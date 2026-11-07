# Tidying: keep one person's saved facts short and in the format of memory_rules.txt, by merging
# the ones that overlap and rewriting old ones. When facts differ and it isn't clear which is right,
# or they disagree with what others saved, the bot asks that person by itself.
#
# During a chat the AI is focused on replying and doesn't do this by itself, so the code starts it:
#   - after a reply, for the person who just spoke, if their memories changed since the last check
#   - once when the bot connects, for everyone whose facts changed since the last tidy
# So a normal message costs nothing extra, and tidy_state.md stops a restart from repeating work or questions.
#
# The AI can only suggest changes. The code checks each one, so a fact can only ever be replaced by
# a new version: never deleted outright, and never mixed with another person's facts.
# Other people's memories are sent without ids, as read-only background for spotting conflicts.
require 'json'
require 'digest'
require_relative './config'
require_relative './prompts'
require_relative './memory_store'
require_relative './memory_items'
require_relative './memory_index'
require_relative './chat_history'
require_relative './message_logger'
require_relative './channel_lock'
require_relative './tidy_state'
require_relative './memory_questions'

TIDY_INSTRUCTIONS = read_prompt("tidy_memory") # loaded once, at startup

TIDY_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: %w[merges question],
  properties: {
    merges: {
      type: "array",
      items: {
        type: "object", additionalProperties: false, required: %w[memory_ids new_texts],
        properties: { memory_ids: { type: "array", items: { type: "string" } }, new_texts: { type: "array", items: { type: "string" } } }
      }
    },
    question: { type: "string" }
  }
}.freeze

# Called after a reply. Asks in the channel if there is a question for this person.
# history: the channel's history, so the question is remembered (mention chats read Discord instead).
# Never raises: a failed tidy must not affect the chat.
def tidy_and_ask(event, client, history = nil)
  server_id = event.server.id
  user_id = event.author.id
  remember_last_channel(server_id, user_id, event.channel.id)
  age_open_question(server_id, user_id)
  question = tidy_memory_if_needed(client, server_id, user_id) || take_pending_question(server_id, user_id)
  return if question.nil?

  sent = event.message.reply!(question, mention_user: false)
  log_bot_reply(event, question)
  add_assistant_message(history, question, message_id: sent&.id) if history
  record_asked_question(server_id, user_id, question)
rescue StandardError => e
  log "⚠️ Could not ask about a memory conflict (#{e.class})."
end

# Returns a question to ask this person, or nil
def tidy_memory_if_needed(client, server_id, user_id)
  return if open_question_text(server_id, user_id) # one question at a time

  memories = with_server_memory_lock(server_id) { memories_to_check(server_id, user_id) }
  return if memories[:own].length + memories[:related].length < MEMORY_TIDY_MIN_FACTS
  return unless memories_changed_since_last_check?(server_id, user_id, memories)

  result = request_tidy(client, memories, tidy_extras(server_id, user_id))
  apply_and_log_tidy(server_id, user_id, result) unless own_facts_already_tidied?(server_id, user_id, memories[:own])
  remember_checked_memories(server_id, user_id) # what is saved now, so a note that was just tidied isn't checked again
  question_from(result)
rescue StandardError => e
  update_tidy_state(server_id, user_id, check_failed_at: Time.now.to_i)
  log "⚠️ Could not tidy memory of user #{user_id} (#{e.class})."
  nil
end

# Discord can connect again later and run bot.ready again, but this only runs the first time.
# In the background, so the bot doesn't wait for it. Returns the thread, or nil if it already ran.
class MemoryTidyStarted
  def initialize = (@started = false; @lock = Mutex.new)

  # true the first time only
  def first_time?
    @lock.synchronize do
      first = !@started
      @started = true
      first
    end
  end

  def make_false = @lock.synchronize { @started = false }
end
MEMORY_TIDY_STARTED = MemoryTidyStarted.new

def start_memory_tidy_once(client, bot, histories = {})
  return nil unless MEMORY_TIDY_STARTED.first_time?

  Thread.new { tidy_all_memory(client, bot, histories) }
end

# Tidies everyone's own facts in every server, even people who haven't talked since, and sends any questions.
# Without a bot (no connection), questions wait until that person next talks.
# histories: the AI channels' histories, so a question sent there is part of the conversation.
def tidy_all_memory(client, bot = nil, histories = {})
  Dir.glob(File.join(MEMORY_DIR, "*")).select { |path| File.directory?(path) }.each do |dir|
    server_id = File.basename(dir)
    owners = with_server_memory_lock(server_id) { personal_memory_items(server_id).map { |item| item[:owner_id] }.uniq }
    owners.each { |user_id| tidy_person_at_startup(client, bot, server_id, user_id, histories) }
  end
end

# --- helpers ---

def tidy_person_at_startup(client, bot, server_id, user_id, histories)
  question = startup_tidy_question(client, server_id, user_id) || take_pending_question(server_id, user_id)
  deliver_memory_question(bot, server_id, user_id, question, histories) if question
rescue StandardError => e
  log "⚠️ Could not tidy memory of user #{user_id} (#{e.class})."
end

# Tidies if the facts changed since the last tidy. Returns a question, or nil.
def startup_tidy_question(client, server_id, user_id)
  own = with_server_memory_lock(server_id) { facts_of_person(server_id, user_id) }
  return nil if own_facts_already_tidied?(server_id, user_id, own)

  result = request_tidy(client, { own: own, related: [] }, tidy_extras(server_id, user_id))
  apply_and_log_tidy(server_id, user_id, result)
  question = question_from(result)
  # So chat doesn't ask about the same thing again. Not if other people's memories exist: the AI hasn't seen those yet.
  remember_checked_memories(server_id, user_id) if question && no_related_memories?(server_id, user_id)
  question
end

# Pings the person where they last talked with the bot. If that isn't possible, the question waits for their next message.
def deliver_memory_question(bot, server_id, user_id, question, histories)
  channel_id = last_channel_of(server_id, user_id)
  channel = bot&.channel(channel_id) if channel_id
  return save_pending_question(server_id, user_id, question) if channel.nil?

  send_memory_question(channel, user_id, question, histories)
  record_asked_question(server_id, user_id, question)
  log "❓ Asked user #{user_id} about their memory in channel #{channel_id}"
rescue StandardError => e
  save_pending_question(server_id, user_id, question)
  log "⚠️ Could not send a memory question to user #{user_id} (#{e.class}). It will wait for their next message."
end

# The bot doesn't receive its own messages, so an AI channel's history only has this question if it is added here.
# key? because the store makes an empty history for any id it is asked about, and only AI channels should have one.
def send_memory_question(channel, user_id, question, histories)
  text = "<@#{user_id}> #{question}"
  with_channel_lock(channel.id) do
    sent = channel.send_message(text)
    add_assistant_message(histories[channel.id], text, message_id: sent&.id) if histories.key?(channel.id)
  end
end

def question_from(result)
  question = result["question"].to_s.strip
  question.empty? ? nil : question
end

def apply_and_log_tidy(server_id, user_id, result)
  changed, written, own = with_server_memory_lock(server_id) do
    counts = apply_tidy(server_id, user_id, result.fetch("merges").to_a)
    [*counts, facts_of_person(server_id, user_id)]
  end
  update_tidy_state(server_id, user_id, tidied: facts_fingerprint(own))
  log "🧹 Tidied memory of user #{user_id}: rewrote #{changed} facts into #{written}" if changed.positive?
end

def own_facts_already_tidied?(server_id, user_id, own)
  tidy_state_of(server_id, user_id)["tidied"] == facts_fingerprint(own)
end

def facts_of_person(server_id, user_id)
  personal_memory_items(server_id).select { |item| item[:owner_id] == user_id.to_s }
end

def memories_to_check(server_id, user_id)
  own = facts_of_person(server_id, user_id)
  mentioned_ids = own.flat_map { |fact| fact[:text].scan(/\d+/) }
  others = all_memory_items(server_id) - own
  { own: own, related: others.select { |item| related_memory?(item, user_id.to_s, mentioned_ids) } }
end

# About this person, or from someone this person's facts mention
def related_memory?(item, user_id, mentioned_ids)
  return true if item[:subject_id] == user_id || item[:text].scan(/\d+/).include?(user_id)

  mentioned_ids.include?(saved_by(item)) || mentioned_ids.include?(item[:subject_id])
end

# Marks the memories as checked straight away, so a request that keeps failing isn't repeated on every message.
# A check that failed is tried again after MEMORY_CHECK_RETRY_SECONDS, so an outage doesn't lose it.
def memories_changed_since_last_check?(server_id, user_id, memories)
  fingerprint = facts_fingerprint(memories[:own] + memories[:related])
  state = tidy_state_of(server_id, user_id)
  return false if state["checked"] == fingerprint && !failed_check_due?(state)

  update_tidy_state(server_id, user_id, checked: fingerprint, check_failed_at: nil)
  true
end

def failed_check_due?(state)
  failed_at = state["check_failed_at"]
  failed_at && Time.now.to_i - failed_at >= MEMORY_CHECK_RETRY_SECONDS
end

def no_related_memories?(server_id, user_id)
  with_server_memory_lock(server_id) { memories_to_check(server_id, user_id)[:related].empty? }
end

def remember_checked_memories(server_id, user_id)
  memories = with_server_memory_lock(server_id) { memories_to_check(server_id, user_id) }
  update_tidy_state(server_id, user_id, checked: facts_fingerprint(memories[:own] + memories[:related]))
end

def facts_fingerprint(facts)
  Digest::SHA1.hexdigest(facts.map { |fact| fact[:id] }.join(","))
end

# What the AI suggests: { "merges" => [{ "memory_ids" => [...], "new_texts" => [...] }], "question" => "..." }
def request_tidy(client, memories, extras)
  response = client.responses.create(parameters: tidy_parameters(tidy_input(memories, extras)))
  JSON.parse(answer_text(response))
end

# What the AI needs besides the memories: what it already asked, and who it could link a name to
def tidy_extras(server_id, user_id)
  { asked: asked_questions_of(server_id, user_id), people: people_in_server(server_id) }
end

# Everyone with a note in this server, like "Minh (777)"
def people_in_server(server_id)
  with_server_memory_lock(server_id) do
    list_memory_files(server_id, "users").filter_map do |path|
      user_id = File.basename(path, ".md")
      note = read_user_note(server_id, user_id)
      "#{note[:name]} (#{user_id})" if note && !note[:name].to_s.empty?
    end
  end
end

def tidy_input(memories, extras)
  own = memories[:own].map { |fact| "[#{fact[:id]}] #{fact[:text]} (#{fact[:date]})" }
  related = memories[:related].map { |item| related_memory_line(item) }
  "## This person's facts\n#{lines_or_none(own)}\n\n" \
    "## Related memories from other people (read-only)\n#{lines_or_none(related)}\n\n" \
    "## Questions you already asked this person\n#{lines_or_none(extras[:asked])}\n\n" \
    "## People in this server\n#{lines_or_none(extras[:people])}"
end

def lines_or_none(lines)
  lines.empty? ? "(none)" : lines.join("\n")
end

# Same text as in the prompt's memory list, without the id: these can't be merged
def related_memory_line(item)
  line = item[:kind] == :personal ? personal_item_line(item) : general_item_line(item)
  line.sub("[#{item[:id]}] ", "")
end

def tidy_parameters(input_text)
  {
    model: OPENAI_MODEL,
    instructions: TIDY_INSTRUCTIONS,
    input: [{ role: "user", content: input_text }],
    max_output_tokens: OPENAI_MAX_OUTPUT_TOKENS,
    reasoning: { effort: COMPACTION_REASONING_EFFORT },
    store: false, # OpenAI does not keep this conversation
    text: { format: { type: "json_schema", name: "tidy_memory", strict: true, schema: TIDY_SCHEMA } }
  }
end

# Applies the changes that pass the checks. Returns [facts replaced, facts written].
# The facts are read again here: anything saved or changed during the request has a new id, so it is skipped.
def apply_tidy(server_id, user_id, merges)
  available = facts_of_person(server_id, user_id).to_h { |fact| [fact[:id], fact] }
  changed = 0
  written = 0
  merges.each do |merge|
    items = items_to_replace(merge, available)
    next if items.nil?

    texts = new_texts_of(merge)
    replace_memory_items(server_id, items, texts)
    items.each { |item| available.delete(item[:id]) } # a fact can only be used in one change
    changed += items.length
    written += texts.length
  end
  rebuild_memory_index(server_id) if changed.positive?
  [changed, written]
end

def new_texts_of(merge)
  merge["new_texts"].to_a.map { |text| one_line(text) }
end

# The facts this change replaces, or nil if it should be skipped.
# There is always at least one new text, so a fact can be rewritten but never just deleted.
def items_to_replace(merge, available)
  ids = merge["memory_ids"].to_a.map(&:to_s).uniq
  texts = new_texts_of(merge)
  return nil if ids.empty? || !new_texts_allowed?(texts)
  return nil unless ids.all? { |id| available.key?(id) }

  items = ids.map { |id| available[id] }
  return nil if items.length == 1 && texts == [items.first[:text]] # nothing would change

  items
end

def new_texts_allowed?(texts)
  return false if texts.empty? || texts.length > MEMORY_TIDY_MAX_NEW_FACTS

  texts.none? { |text| text.empty? || text.length > REMEMBER_FACT_MAX_CHARS }
end
