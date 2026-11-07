require_relative "test_helper"
require "json"
require "faraday"
require_relative "../config"
require_relative "../ai_chat"
require_relative "../compaction"

# Compaction: when a channel's history gets too big, the oldest turns are summarized in ONE request,
# saved to files (channel summary, personality notes, events), and dropped from RAM.
class CompactionTest < Minitest::Test
  def setup
    clear_test_memory
    LOGS.clear
  end

  # turns = number of user + assistant pairs. Discord ids are 1, 2, 3...
  def chat(turns)
    history = []
    turns.times do |i|
      add_user_message(history, "Bach", 123, "message #{i}", Time.now, message_id: (2 * i) + 1)
      add_assistant_message(history, "reply #{i}", message_id: (2 * i) + 2)
    end
    history
  end

  def test_instructions_use_the_bots_name
    instructions = compaction_parameters("x", "Mochi")[:instructions]
    assert_includes instructions, "Discord bot called Mochi"
    refute_includes instructions, "{bot_name}"
    refute_includes instructions, "Cake"
  end

  def result(personalities: [], events: [])
    { summary: "They chatted.", events: events, user_personalities: personalities }.to_json
  end

  def bach(personality = "Chatty.")
    { user_id: "123", name: "Bach", personality: personality, description: "chatty" }
  end

  def test_small_history_needs_no_compaction
    refute needs_compaction?(chat(5))
  end

  def test_big_history_needs_compaction
    assert needs_compaction?(chat(23)) # 46 messages > 45
  end

  def test_split_keeps_the_newest_turns_under_the_low_mark
    history = chat(23)
    old, kept = split_for_compaction(history)
    assert kept.length <= COMPACT_TARGET_MESSAGES
    assert_equal history, old + kept
    assert_equal "user", kept.first[:role]
    assert_equal 46, history.length # the history itself is not changed
  end

  def test_compaction_shrinks_history_to_the_low_mark_and_saves_the_summary
    history = chat(23)
    assert compact_history(FakeClient.new(answers: [result]), history, 1, 555, "Mochi")
    assert history.length <= COMPACT_TARGET_MESSAGES
    summary = read_channel_summary(1, 555)
    assert_equal "They chatted.", summary[:text]
    assert_equal history.first[:message_id] - 1, summary[:last_message_id]
  end

  def test_one_request_per_compaction
    client = FakeClient.new(answers: [result])
    compact_history(client, chat(23), 1, 555, "Mochi")
    assert_equal 1, client.requests.length
    request = client.requests.first
    assert_equal false, request[:store]
    assert_equal "json_schema", request[:text][:format][:type]
  end

  def test_request_contains_old_messages_and_current_summary
    write_channel_summary(1, 555, "Earlier they planned a trip.", 0)
    client = FakeClient.new(answers: [result])
    compact_history(client, chat(23), 1, 555, "Mochi")
    sent = client.requests.first[:input].first[:content]
    assert_includes sent, "Earlier they planned a trip."
    assert_includes sent, "Bach (123): message 0"
    assert_includes sent, "Mochi: reply 0"
  end

  def test_personality_only_for_people_who_spoke
    bob = { user_id: "456", name: "Bob", personality: "Bad.", description: "bad" }
    compact_history(FakeClient.new(answers: [result(personalities: [bach, bob])]), chat(23), 1, 555, "Mochi")
    assert_equal "Chatty.", read_user_note(1, 123)[:personality]
    assert_nil read_user_note(1, 456)
  end

  def test_compaction_keeps_remembered_facts
    append_remembered_fact(1, 123, "Bach", "likes pho")
    compact_history(FakeClient.new(answers: [result(personalities: [bach])]), chat(23), 1, 555, "Mochi")
    assert_equal 1, read_user_note(1, 123)[:remembered].length
  end

  def test_invalid_event_from_model_is_skipped
    events = [{ title: "Party", when: "soon", details: "" }, { title: "Cup", when: "2099-01-02", details: "" }]
    compact_history(FakeClient.new(answers: [result(events: events)]), chat(23), 1, 555, "Mochi")
    assert_equal ["Cup"], list_event_notes(1).map { |event| event[:title] }
  end

  def test_index_is_rebuilt
    compact_history(FakeClient.new(answers: [result(personalities: [bach])]), chat(23), 1, 555, "Mochi")
    assert_includes read_memory_file(1, "MEMORY.md"), "Bach (123): chatty"
  end

  def test_failure_keeps_history_and_logs
    history = chat(23)
    refute compact_history(FakeClient.new(error: Faraday::ConnectionFailed.new("down")), history, 1, 555, "Mochi")
    assert_equal 46, history.length
    assert_includes LOGS.last, "Compaction failed"
  end

  def test_bad_json_is_a_failure
    history = chat(23)
    refute compact_history(FakeClient.new(answers: ["not json"]), history, 1, 555, "Mochi")
    assert_equal 46, history.length
  end

  def test_json_without_a_summary_is_a_failure
    history = chat(23)
    refute compact_history(FakeClient.new(answers: ['{"events":[]}']), history, 1, 555, "Mochi")
    assert_equal 46, history.length
  end

  def test_missing_ids_keep_previous_summary_id
    write_channel_summary(1, 555, "old", 7)
    history = chat(23).each { |message| message[:message_id] = nil }
    compact_history(FakeClient.new(answers: [result]), history, 1, 555, "Mochi")
    assert_equal 7, read_channel_summary(1, 555)[:last_message_id]
  end
end
