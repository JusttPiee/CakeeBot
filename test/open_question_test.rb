require_relative "test_helper"
require "json"
require "faraday"
require_relative "../config"
require_relative "../ai_channel_chat"
require_relative "../memory_tidy"
require_relative "ai_channel_chat_test" # FakeAiEvent

# After the bot asks about a memory conflict, the answer has to reach memory:
# the AI is told about the open question, and tidying knows what was already asked.
class OpenQuestionTest < Minitest::Test
  NOW = Time.new(2026, 11, 7, 12, 0)
  QUESTION = "Do you prefer Better Big Boss or Bloo?".freeze
  CONTEXT = { server_id: 1, channel_id: nil, requester_id: 123, requester_name: "Bach" }.freeze

  class FakeChannel
    FakeMessage = Struct.new(:id)
    attr_reader :sent

    def initialize = @sent = []
    def id = 555

    def send_message(text)
      @sent << text
      FakeMessage.new(77)
    end
  end

  class FakeBot
    def initialize(channel) = @channel = channel
    def channel(_id) = @channel
  end

  def setup
    clear_test_memory
    LOGS.clear
    @channel = FakeChannel.new
    @bot = FakeBot.new(@channel)
  end

  def save(text, user_id = 123, name = "Bach") = append_remembered_fact(1, user_id, name, text, NOW)
  def asks = FakeClient.new(answers: [{ merges: [], question: QUESTION }.to_json])

  # The instructions the chat AI gets when this person sends a message
  def chat_instructions(context = CONTEXT)
    client = FakeClient.new(answers: ["Hi!"])
    ask_ai(client, [], "Cake", context)
    client.requests.first[:instructions]
  end

  # --- A question sent at startup is part of the conversation ---

  def test_a_startup_question_goes_into_that_channels_history
    save("call me Boss")
    remember_last_channel(1, 123, 555)
    histories = { 555 => [] }
    tidy_all_memory(asks, @bot, histories)
    assert_equal [{ role: "assistant", content: "<@123> #{QUESTION}", message_id: 77 }], histories[555]
  end

  def test_a_channel_without_ai_mode_gets_no_history
    save("call me Boss")
    remember_last_channel(1, 123, 555)
    histories = create_history_store
    tidy_all_memory(asks, @bot, histories)
    assert_equal ["<@123> #{QUESTION}"], @channel.sent
    refute histories.key?(555)
  end

  def test_the_background_start_passes_the_histories_on
    save("call me Boss")
    remember_last_channel(1, 123, 555)
    MEMORY_TIDY_STARTED.make_false
    histories = { 555 => [] }
    start_memory_tidy_once(asks, @bot, histories)&.join
    assert_equal 1, histories[555].length
  end

  # --- The AI is told about the open question ---

  def test_no_question_means_nothing_extra_in_the_prompt
    refute_includes chat_instructions, "still not settled"
  end

  def test_a_question_asked_at_startup_reaches_the_prompt
    save("call me Boss")
    remember_last_channel(1, 123, 555)
    tidy_all_memory(asks, @bot)
    assert_includes chat_instructions, QUESTION
  end

  def test_a_question_asked_in_chat_reaches_the_prompt
    save("call me Boss")
    save("call me Bloo")
    answer_ai_channel_message(FakeAiEvent.new("hello"), asks_after_reply, [])
    assert_includes chat_instructions, QUESTION
  end

  def asks_after_reply = FakeClient.new(answers: ["Hi!", { merges: [], question: QUESTION }.to_json])

  def test_only_the_person_who_was_asked_sees_it
    record_asked_question(1, 123, QUESTION)
    refute_includes chat_instructions(CONTEXT.merge(requester_id: 789, requester_name: "Jack")), QUESTION
  end

  def test_the_prompt_says_to_change_memory_in_the_same_reply
    record_asked_question(1, 123, QUESTION)
    prompt = chat_instructions
    assert_includes prompt, "update_memory"
    assert_includes prompt, "forget_memory"
    assert_includes prompt, "in this same reply"
  end

  def test_the_prompt_keeps_the_answer_in_the_senders_own_memory
    record_asked_question(1, 123, QUESTION)
    assert_includes chat_instructions, "must end up with one memory of their own that says the answer"
  end

  def test_the_rules_say_earlier_memory_changes_really_happened
    assert_includes read_prompt("memory_rules"), "Tool steps don't appear in the conversation"
  end

  # --- When the question closes ---

  def test_a_change_in_memory_closes_the_question
    save("call me Boss")
    record_asked_question(1, 123, QUESTION)
    save("call me Bloo")
    age_open_question(1, 123)
    assert_nil open_question_text(1, 123)
  end

  def test_it_closes_after_a_few_messages_without_an_answer
    save("call me Boss")
    record_asked_question(1, 123, QUESTION)
    (OPEN_QUESTION_MAX_MESSAGES - 1).times { age_open_question(1, 123) }
    assert_equal QUESTION, open_question_text(1, 123)
    age_open_question(1, 123)
    assert_nil open_question_text(1, 123)
  end

  def test_a_reply_counts_as_one_of_those_messages
    save("call me Boss")
    save("call me Bloo")
    record_asked_question(1, 123, QUESTION)
    OPEN_QUESTION_MAX_MESSAGES.times do |number|
      answer_ai_channel_message(FakeAiEvent.new("message #{number}"), FakeClient.new(answers: ["Hi!", { merges: [], question: "" }.to_json]), [])
    end
    assert_nil open_question_text(1, 123)
  end

  def test_someone_elses_message_does_not_use_it_up
    save("call me Boss")
    record_asked_question(1, 123, QUESTION)
    age_open_question(1, 789)
    assert_equal QUESTION, open_question_text(1, 123)
  end

  # --- Tidying knows what was already asked ---

  def test_tidying_is_told_what_was_already_asked
    save("call me Boss")
    save("call me Bloo")
    record_asked_question(1, 123, QUESTION)
    update_tidy_state(1, 123, open_question: nil)
    client = FakeClient.new(answers: [{ merges: [], question: "" }.to_json])
    tidy_memory_if_needed(client, 1, 123)
    assert_includes client.requests.first[:input].to_s, "Questions you already asked this person"
    assert_includes client.requests.first[:input].to_s, QUESTION
  end

  def test_startup_tidying_is_told_too
    save("call me Boss")
    record_asked_question(1, 123, QUESTION)
    client = FakeClient.new(answers: [{ merges: [], question: "" }.to_json])
    tidy_all_memory(client)
    assert_includes client.requests.first[:input].to_s, QUESTION
  end

  def test_only_the_newest_questions_are_kept
    (ASKED_QUESTIONS_KEPT + 1).times { |number| record_asked_question(1, 123, "Question #{number}?") }
    kept = asked_questions_of(1, 123)
    assert_equal ASKED_QUESTIONS_KEPT, kept.length
    refute_includes kept, "Question 0?"
  end

  # --- One question at a time ---

  def test_nothing_new_is_checked_while_a_question_is_open
    save("call me Boss")
    save("call me Bloo")
    record_asked_question(1, 123, QUESTION)
    client = asks
    assert_nil tidy_memory_if_needed(client, 1, 123)
    assert_empty client.requests
  end

  # --- A failed check isn't lost ---

  def test_a_failed_check_is_not_repeated_straight_away
    save("a")
    save("b")
    tidy_memory_if_needed(FakeClient.new(error: Faraday::ConnectionFailed.new("down")), 1, 123)
    client = asks
    assert_nil tidy_memory_if_needed(client, 1, 123)
    assert_empty client.requests
  end

  def test_a_failed_check_is_tried_again_after_the_wait
    save("a")
    save("b")
    tidy_memory_if_needed(FakeClient.new(error: Faraday::ConnectionFailed.new("down")), 1, 123)
    update_tidy_state(1, 123, check_failed_at: Time.now.to_i - MEMORY_CHECK_RETRY_SECONDS - 1)
    assert_equal QUESTION, tidy_memory_if_needed(asks, 1, 123)
  end

  def test_a_check_that_worked_is_not_tried_again
    save("a")
    save("b")
    tidy_memory_if_needed(FakeClient.new(error: Faraday::ConnectionFailed.new("down")), 1, 123)
    update_tidy_state(1, 123, check_failed_at: Time.now.to_i - MEMORY_CHECK_RETRY_SECONDS - 1)
    tidy_memory_if_needed(FakeClient.new(answers: [{ merges: [], question: "" }.to_json]), 1, 123)
    client = asks
    tidy_memory_if_needed(client, 1, 123)
    assert_empty client.requests
  end

  # --- A startup question doesn't hide other people's memories ---

  def test_other_peoples_memories_are_checked_after_a_startup_question
    save("Prefers Small Boss")
    save("Prefers Medium Boss")
    save("Bach (123) prefers Big Boss", 456, "Pie")
    remember_last_channel(1, 123, 555)
    tidy_all_memory(FakeClient.new(answers: [{ merges: [], question: QUESTION }.to_json, { merges: [], question: "" }.to_json]), @bot)
    update_tidy_state(1, 123, open_question: nil) # the question was ignored
    client = FakeClient.new(answers: [{ merges: [], question: "Pie saved Big Boss. Which is right?" }.to_json])
    assert_equal "Pie saved Big Boss. Which is right?", tidy_memory_if_needed(client, 1, 123)
    assert_includes client.requests.first[:input].to_s, "Bach (123) prefers Big Boss"
  end

  def test_nothing_new_to_check_after_a_startup_question_means_no_request
    save("Prefers Small Boss")
    save("Prefers Medium Boss")
    remember_last_channel(1, 123, 555)
    tidy_all_memory(asks, @bot)
    update_tidy_state(1, 123, open_question: nil)
    client = asks
    assert_nil tidy_memory_if_needed(client, 1, 123)
    assert_empty client.requests
  end

  # --- A waiting question can go out of date ---

  def test_a_waiting_question_is_dropped_when_the_memories_changed
    save("Prefers Boss")
    save_pending_question(1, 123, QUESTION)
    save("Prefers Chief")
    assert_nil take_pending_question(1, 123)
  end

  def test_a_waiting_question_is_kept_when_nothing_changed
    save("Prefers Boss")
    save_pending_question(1, 123, QUESTION)
    assert_equal QUESTION, take_pending_question(1, 123)
  end

  # --- Names that can't be linked to someone ---

  def test_tidying_is_told_who_is_known_in_the_server
    save("Wants to know when Minh is online")
    save("Likes pho", 777, "Minh")
    client = FakeClient.new(answers: [{ merges: [], question: "" }.to_json])
    tidy_all_memory(client)
    assert_includes client.requests.first[:input].to_s, "## People in this server"
    assert_includes client.requests.first[:input].to_s, "Minh (777)"
  end

  def test_the_rules_say_to_ask_when_a_name_cant_be_linked
    rules = read_prompt("memory_rules")
    assert_includes rules, "ask who they mean"
    assert_includes rules, "@mention"
  end

  def test_the_tidy_prompt_says_to_ask_when_a_name_cant_be_linked
    prompt = read_prompt("tidy_memory")
    assert_includes prompt, "People in this server"
    assert_includes prompt, "Never guess a user id"
  end

  # --- The rules for tidying ---

  def test_the_tidy_prompt_says_not_to_ask_again
    assert_includes read_prompt("tidy_memory"), "Questions you already asked this person"
  end

  def test_the_tidy_prompt_says_an_insult_is_not_a_conflict
    prompt = read_prompt("tidy_memory")
    assert_includes prompt, "is bad at Valorant"
    assert_includes prompt, "never a conflict"
  end
end
