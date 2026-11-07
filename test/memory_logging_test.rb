require_relative "test_helper"
require "json"
require "faraday"
require_relative "../config"
require_relative "../ai_channel_chat"
require_relative "../memory_tidy"
require_relative "ai_channel_chat_test" # FakeAiEvent

# Everything the bot does with memory can be followed in the terminal.
class MemoryLoggingTest < Minitest::Test
  NOW = Time.new(2026, 11, 7, 12, 0)
  BACH = { server_id: 1, channel_id: nil, requester_id: 123, requester_name: "Bach" }.freeze
  JACK = { server_id: 1, channel_id: nil, requester_id: 789, requester_name: "Jack" }.freeze

  def setup
    clear_test_memory
    LOGS.clear
  end

  def save(text, user_id = 123, name = "Bach") = append_remembered_fact(1, user_id, name, text, NOW)
  def ids(user_id = 123) = personal_memory_items(1).select { |item| item[:owner_id] == user_id.to_s }.map { |item| item[:id] }
  def logged?(*parts) = LOGS.any? { |line| parts.all? { |part| line.include?(part) } }
  def tidy_answer(merges: [], question: "") = { merges: merges, question: question }.to_json

  # --- Reading ---

  def test_reading_a_note_is_logged
    save("likes pho")
    run_read_memory({ "path" => "users/123.md" }, BACH)
    assert logged?("read_memory", "Bach (123)", "users/123.md")
  end

  # --- Refused changes ---

  def test_a_refused_update_is_logged
    save("likes pho")
    run_update_memory({ "memory_id" => ids.first, "new_text" => "hates pho" }, JACK)
    assert logged?("update_memory refused", "Jack (789)", "likes pho")
  end

  def test_a_refused_forget_is_logged
    save("likes pho")
    run_forget_memory({ "memory_id" => ids.first }, JACK)
    assert logged?("forget_memory refused", "Jack (789)", "likes pho")
  end

  def test_a_refused_merge_is_logged
    save("likes pho")
    save("likes bun")
    run_merge_memories({ "memory_ids" => ids, "new_text" => "hacked" }, JACK)
    assert logged?("merge_memories refused", "Jack (789)")
  end

  def test_an_allowed_change_is_not_logged_as_refused
    save("likes pho")
    run_update_memory({ "memory_id" => ids.first, "new_text" => "likes bun" }, BACH)
    refute logged?("refused")
  end

  # --- Questions asked in chat ---

  def test_a_question_asked_in_chat_is_logged
    save("call me Boss")
    save("call me Bloo")
    client = FakeClient.new(answers: ["Hi!", tidy_answer(question: "Boss or Bloo?")])
    answer_ai_channel_message(FakeAiEvent.new("hello"), client, [])
    assert logged?("❓", "user 123", "channel 555")
  end

  # --- What tidying did ---

  def test_tidying_logs_the_old_and_new_text
    save("call me Boss")
    save("please call me Boss")
    merges = [{ memory_ids: ids, new_texts: ["Prefers to be called Boss"] }]
    tidy_memory_if_needed(FakeClient.new(answers: [tidy_answer(merges: merges)]), 1, 123)
    assert logged?("user 123", "call me Boss", "please call me Boss", "Prefers to be called Boss")
  end

  def test_a_check_that_changed_nothing_is_logged
    save("likes pho")
    save("plays Chamber")
    tidy_memory_if_needed(FakeClient.new(answers: [tidy_answer]), 1, 123)
    assert logged?("Checked memory of user 123", "no changes")
  end

  def test_a_check_of_facts_that_were_already_tidied_is_logged
    save("likes pho")
    save("plays Chamber")
    tidy_all_memory(FakeClient.new(answers: [tidy_answer]))
    LOGS.clear
    tidy_memory_if_needed(FakeClient.new(answers: [tidy_answer]), 1, 123)
    assert logged?("Checked memory of user 123", "no changes")
  end

  def test_a_check_that_changed_something_does_not_say_no_changes
    save("call me Boss")
    save("please call me Boss")
    merges = [{ memory_ids: ids, new_texts: ["Prefers to be called Boss"] }]
    tidy_memory_if_needed(FakeClient.new(answers: [tidy_answer(merges: merges)]), 1, 123)
    refute logged?("no changes")
  end
end
