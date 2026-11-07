require_relative "test_helper"
require "json"
require "faraday"
require_relative "../config"
require_relative "../ai_channel_chat"
require_relative "../memory_tidy"

# After a reply, code asks the AI to merge overlapping facts of the person who just spoke.
class MemoryTidyTest < Minitest::Test
  NOW = Time.new(2026, 11, 7, 12, 0)

  def setup
    clear_test_memory
    LOGS.clear
  end

  def save(text, user_id = 123, name = "Bach") = append_remembered_fact(1, user_id, name, text, NOW)
  def texts(user_id = 123) = personal_memory_items(1).select { |item| item[:owner_id] == user_id.to_s }.map { |item| item[:text] }
  def ids(user_id = 123) = personal_memory_items(1).select { |item| item[:owner_id] == user_id.to_s }.map { |item| item[:id] }
  def answer(merges) = { merges: merges }.to_json
  def merge_of(memory_ids, *new_texts) = { memory_ids: memory_ids, new_texts: new_texts }
  def tidy(client) = tidy_memory_if_needed(client, 1, 123)

  def test_overlapping_facts_become_one
    save("call me Boss")
    save("please call me Boss")
    save("likes pho")
    tidy(FakeClient.new(answers: [answer([merge_of(ids.first(2), "call me Boss")])]))
    assert_equal ["call me Boss", "likes pho"], texts
  end

  def test_the_index_is_updated
    save("call me Boss")
    save("please call me Boss")
    tidy(FakeClient.new(answers: [answer([merge_of(ids, "call me The Boss")])]))
    assert_includes read_memory_file(1, "MEMORY.md"), "call me The Boss"
  end

  def test_only_this_persons_facts_are_sent
    save("call me Boss")
    save("please call me Boss")
    save("a secret of Pie", 456, "Pie")
    client = FakeClient.new(answers: [answer([])])
    tidy(client)
    sent = client.requests.first
    assert_includes sent[:input].to_s, "call me Boss"
    refute_includes sent[:input].to_s, "a secret of Pie"
    assert_equal false, sent[:store]
    assert_equal "json_schema", sent[:text][:format][:type]
  end

  def test_the_instructions_come_from_the_prompt_file
    save("a")
    save("b")
    client = FakeClient.new(answers: [answer([])])
    tidy(client)
    assert_equal read_prompt("tidy_memory"), client.requests.first[:instructions]
  end

  # --- When it runs ---

  def test_one_fact_needs_no_request
    save("likes pho")
    client = FakeClient.new
    tidy(client)
    assert_empty client.requests
  end

  def test_no_facts_needs_no_request
    client = FakeClient.new
    tidy(client)
    assert_empty client.requests
  end

  def test_unchanged_facts_are_not_checked_twice
    save("a")
    save("b")
    client = FakeClient.new(answers: [answer([])])
    2.times { tidy(client) }
    assert_equal 1, client.requests.length
  end

  def test_a_new_fact_means_checking_again
    save("a")
    save("b")
    client = FakeClient.new(answers: [answer([])])
    tidy(client)
    save("c")
    tidy(client)
    assert_equal 2, client.requests.length
  end

  def test_a_tidied_note_is_not_checked_again
    save("call me Boss")
    save("please call me Boss")
    client = FakeClient.new(answers: [answer([merge_of(ids, "call me Boss")])])
    2.times { tidy(client) }
    assert_equal 1, client.requests.length
  end

  # --- What the code refuses, whatever the AI answers ---

  def test_another_persons_fact_is_never_merged
    save("mine")
    save("mine too")
    save("theirs", 456, "Pie")
    tidy(FakeClient.new(answers: [answer([merge_of([ids.first, ids(456).first], "hacked")])]))
    assert_equal ["mine", "mine too"], texts
    assert_equal ["theirs"], texts(456)
  end

  def test_an_unknown_id_skips_that_merge_only
    save("a")
    save("b")
    save("c")
    save("d")
    all = ids
    tidy(FakeClient.new(answers: [answer([merge_of([all[0], "nope"], "x"), merge_of([all[2], all[3]], "c and d")])]))
    assert_equal ["a", "b", "c and d"], texts
  end

  # --- Rewriting old facts into the new format ---

  def test_one_old_fact_can_be_rewritten
    save("I am on TFC")
    save("likes pho")
    tidy(FakeClient.new(answers: [answer([merge_of([ids.first], "Is on TFC")])]))
    assert_equal ["Is on TFC", "likes pho"], texts
  end

  def test_a_fact_with_two_ideas_can_be_split
    save("call me Boss, likes pho")
    save("plays Chamber")
    tidy(FakeClient.new(answers: [answer([merge_of([ids.first], "call me Boss", "likes pho")])]))
    assert_equal ["call me Boss", "plays Chamber", "likes pho"], texts
  end

  def test_no_new_text_cannot_delete_a_fact
    save("a")
    save("b")
    tidy(FakeClient.new(answers: [answer([merge_of([ids.first])])]))
    assert_equal %w[a b], texts
  end

  def test_one_empty_text_skips_the_whole_rewrite
    save("a")
    save("b")
    tidy(FakeClient.new(answers: [answer([merge_of([ids.first], "new", " ")])]))
    assert_equal %w[a b], texts
  end

  def test_a_fact_cannot_be_split_into_too_many
    save("a")
    save("b")
    many = (1..(MEMORY_TIDY_MAX_NEW_FACTS + 1)).map { |number| "fact #{number}" }
    tidy(FakeClient.new(answers: [answer([merge_of([ids.first], *many)])]))
    assert_equal %w[a b], texts
  end

  def test_rewriting_to_the_same_text_changes_nothing
    save("a")
    save("b")
    before = read_memory_file(1, "users/123.md")
    tidy(FakeClient.new(answers: [answer([merge_of([ids.first], "a")])]))
    assert_equal before, read_memory_file(1, "users/123.md")
    refute(LOGS.any? { |line| line.include?("Tidied") })
  end

  def test_the_rules_for_rewriting_are_in_the_prompt
    prompt = read_prompt("tidy_memory")
    assert_includes prompt, "new_texts"
    assert_includes prompt, "already follows"
  end

  # --- Tidying everyone when the bot starts ---

  def test_everyone_is_tidied_in_every_server
    save("I am on TFC")
    append_remembered_fact(2, 456, "Pie", "I play Chamber", NOW)
    client = FakeClient.new(answers: [answer([])])
    tidy_all_memory(client)
    assert_equal 2, client.requests.length
  end

  def test_a_person_with_one_old_fact_is_rewritten_at_startup
    save("I am on TFC")
    id = ids.first
    tidy_all_memory(FakeClient.new(answers: [answer([merge_of([id], "Is on TFC")])]))
    assert_equal ["Is on TFC"], texts
  end

  def test_startup_sends_only_each_persons_own_facts
    save("mine")
    save("user 123 prefers Big Boss", 456, "Pie")
    client = FakeClient.new(answers: [answer([])])
    tidy_all_memory(client)
    mine = client.requests.find { |request| request[:input].to_s.include?("mine") }
    refute_includes mine[:input].to_s, "prefers Big Boss"
  end

  def test_a_question_at_startup_is_not_lost
    save("call me Small Boss")
    save("also call me Small Boss")
    tidy_all_memory(FakeClient.new(answers: [question_answer("Which is right?")]))
    assert_equal "Which is right?", take_pending_question(1, 123)
  end

  def test_one_failure_does_not_stop_the_others
    save("mine")
    append_remembered_fact(1, 456, "Pie", "I play Chamber", NOW)
    client = Object.new
    def client.responses = self
    def client.create(parameters:)
      raise Faraday::ConnectionFailed, "down" if parameters[:input].to_s.include?("mine")

      { "status" => "completed", "output" => [{ "type" => "message", "content" => [{ "text" => { merges: [], question: "" }.to_json }] }] }
    end
    tidy_all_memory(client)
    assert_equal 1, LOGS.count { |line| line.include?("Could not tidy") }
  end

  # --- Not rewriting the same note again and again ---

  def test_a_second_startup_with_the_same_facts_sends_nothing
    save("a")
    tidy_all_memory(FakeClient.new(answers: [answer([])]))
    client = FakeClient.new(answers: [answer([])])
    tidy_all_memory(client)
    assert_empty client.requests
  end

  def test_a_second_startup_after_a_rewrite_sends_nothing
    save("I am on TFC")
    id = ids.first
    tidy_all_memory(FakeClient.new(answers: [answer([merge_of([id], "Is on TFC")])]))
    client = FakeClient.new(answers: [answer([])])
    tidy_all_memory(client)
    assert_empty client.requests
  end

  def test_a_new_fact_means_tidying_again_at_startup
    save("a")
    tidy_all_memory(FakeClient.new(answers: [answer([])]))
    save("b")
    client = FakeClient.new(answers: [answer([])])
    tidy_all_memory(client)
    assert_equal 1, client.requests.length
  end

  def test_the_state_survives_a_restart
    save("a")
    tidy_all_memory(FakeClient.new(answers: [answer([])]))
    client = FakeClient.new(answers: [answer([])])
    tidy_all_memory(client)
    assert_empty client.requests
  end

  def test_chat_doesnt_rewrite_facts_that_were_already_tidied
    save("a")
    save("b")
    tidy_all_memory(FakeClient.new(answers: [answer([])]))
    all = ids
    tidy(FakeClient.new(answers: [answer([merge_of(all, "reworded")])]))
    assert_equal %w[a b], texts
  end

  def test_chat_still_asks_about_conflicts_after_a_tidy
    save("a")
    save("b")
    tidy_all_memory(FakeClient.new(answers: [answer([])]))
    assert_equal "Which?", tidy(FakeClient.new(answers: [question_answer("Which?")]))
  end

  def test_chat_tidies_facts_that_changed_since_the_last_tidy
    save("a")
    save("b")
    tidy_all_memory(FakeClient.new(answers: [answer([])]))
    save("a again")
    all = ids
    tidy(FakeClient.new(answers: [answer([merge_of([all[0], all[2]], "a")])]))
    assert_equal %w[a b], texts
  end

  def test_a_failed_startup_tidy_is_tried_again_next_time
    save("a")
    tidy_all_memory(FakeClient.new(error: Faraday::ConnectionFailed.new("down")))
    client = FakeClient.new(answers: [answer([])])
    tidy_all_memory(client)
    assert_equal 1, client.requests.length
  end

  def test_the_state_file_is_not_in_the_prompt
    save("a")
    tidy_all_memory(FakeClient.new(answers: [answer([])]))
    refute_includes rebuild_memory_index(1), "tidy_state"
  end

  # --- Dates ---

  def test_a_rewritten_fact_keeps_its_date
    append_remembered_fact(1, 123, "Bach", "I am on TFC", Time.new(2026, 11, 1))
    append_remembered_fact(1, 123, "Bach", "likes pho", Time.new(2026, 11, 2))
    tidy(FakeClient.new(answers: [answer([merge_of([ids.first], "Is on TFC")])]))
    assert_equal "2026-11-01", personal_memory_items(1).find { |item| item[:text] == "Is on TFC" }[:date]
  end

  def test_a_merged_fact_gets_the_newest_date
    append_remembered_fact(1, 123, "Bach", "call me Boss", Time.new(2026, 11, 1))
    append_remembered_fact(1, 123, "Bach", "call me Chief", Time.new(2026, 11, 5))
    tidy(FakeClient.new(answers: [answer([merge_of(ids, "call me Chief")])]))
    assert_equal "2026-11-05", personal_memory_items(1).first[:date]
  end

  def test_split_facts_keep_the_date_too
    append_remembered_fact(1, 123, "Bach", "call me Boss, likes pho", Time.new(2026, 11, 1))
    save("plays Chamber")
    tidy(FakeClient.new(answers: [answer([merge_of([ids.first], "call me Boss", "likes pho")])]))
    assert_equal "2026-11-01", personal_memory_items(1).find { |item| item[:text] == "likes pho" }[:date]
  end

  def test_no_memory_at_all_is_fine
    client = FakeClient.new
    tidy_all_memory(client)
    assert_empty client.requests
  end

  def test_empty_text_cannot_delete_facts
    save("a")
    save("b")
    tidy(FakeClient.new(answers: [answer([merge_of(ids, "  ")])]))
    assert_equal %w[a b], texts
  end

  def test_too_long_text_is_skipped
    save("a")
    save("b")
    tidy(FakeClient.new(answers: [answer([merge_of(ids, "x" * (REMEMBER_FACT_MAX_CHARS + 1))])]))
    assert_equal %w[a b], texts
  end

  def test_a_fact_is_only_used_in_one_merge
    save("a")
    save("b")
    save("c")
    all = ids
    tidy(FakeClient.new(answers: [answer([merge_of([all[0], all[1]], "ab"), merge_of([all[1], all[2]], "bc")])]))
    assert_equal %w[ab c], texts
  end

  def test_bad_json_changes_nothing_and_is_logged
    save("a")
    save("b")
    tidy(FakeClient.new(answers: ["not json"]))
    assert_equal %w[a b], texts
    assert_includes LOGS.last, "tidy"
  end

  def test_an_openai_error_changes_nothing_and_is_logged
    save("a")
    save("b")
    tidy(FakeClient.new(error: Faraday::ConnectionFailed.new("down")))
    assert_equal %w[a b], texts
    assert_includes LOGS.last, "tidy"
  end

  def test_personality_is_kept
    write_user_personality(1, 123, "Bach", "Chatty.", "chatty")
    save("a")
    save("b")
    tidy(FakeClient.new(answers: [answer([merge_of(ids, "ab")])]))
    assert_equal "Chatty.", read_user_note(1, 123)[:personality]
  end

  # --- Asking about conflicts with related people ---

  def question_answer(text) = { merges: [], question: text }.to_json

  def test_a_conflict_comes_back_as_a_question
    save("call me Small Boss")
    save("user 123 prefers Big Boss", 456, "Pie")
    question = tidy(FakeClient.new(answers: [question_answer("Pie saved Big Boss, you said Small Boss. Which is right?")]))
    assert_includes question, "Which is right?"
  end

  def test_no_conflict_means_no_question
    save("a")
    save("b")
    assert_nil tidy(FakeClient.new(answers: [question_answer("  ")]))
  end

  def test_no_request_means_no_question
    assert_nil tidy(FakeClient.new)
  end

  def test_a_failed_request_means_no_question
    save("a")
    save("b")
    assert_nil tidy(FakeClient.new(error: Faraday::ConnectionFailed.new("down")))
  end

  def test_memories_from_others_that_mention_this_person_are_sent
    save("call me Small Boss")
    save("user 123 prefers Big Boss", 456, "Pie")
    client = FakeClient.new(answers: [answer([])])
    tidy(client)
    assert_includes client.requests.first[:input].to_s, "user 123 prefers Big Boss"
    assert_includes client.requests.first[:input].to_s, "Pie (456)"
  end

  def test_general_notes_about_this_person_are_sent
    save("I am great at Valorant")
    append_general_note(1, 456, "Pie", 123, "Bach", "is bad at Valorant", NOW)
    client = FakeClient.new(answers: [answer([])])
    tidy(client)
    assert_includes client.requests.first[:input].to_s, "Pie (456) says about Bach (123): is bad at Valorant"
  end

  def test_memories_of_people_this_person_mentions_are_sent
    save("user 456 prefers Big Boss")
    save("call me Small Boss", 456, "Pie")
    client = FakeClient.new(answers: [answer([])])
    tidy(client)
    assert_includes client.requests.first[:input].to_s, "call me Small Boss"
  end

  def test_unrelated_memories_are_not_sent
    save("likes pho")
    save("likes bun", 456, "Pie")
    save("about someone else", 789, "Jack")
    client = FakeClient.new
    tidy(client)
    assert_empty client.requests
  end

  def test_related_memories_cannot_be_merged
    save("call me Small Boss")
    save("also call me Small Boss")
    save("user 123 prefers Big Boss", 456, "Pie")
    theirs = ids(456).first
    tidy(FakeClient.new(answers: [answer([merge_of([ids.first, theirs], "hacked")])]))
    assert_equal ["user 123 prefers Big Boss"], texts(456)
    assert_equal 2, texts.length
  end

  def test_related_memories_have_no_id_to_merge_with
    save("call me Small Boss")
    save("user 123 prefers Big Boss", 456, "Pie")
    client = FakeClient.new(answers: [answer([])])
    tidy(client)
    refute_includes client.requests.first[:input].to_s, ids(456).first
  end

  def test_a_new_related_memory_means_checking_again
    save("a")
    save("b")
    client = FakeClient.new(answers: [answer([])])
    tidy(client)
    save("user 123 prefers Big Boss", 456, "Pie")
    tidy(client)
    assert_equal 2, client.requests.length
  end

  def test_the_same_conflict_is_not_asked_twice
    save("call me Small Boss")
    save("user 123 prefers Big Boss", 456, "Pie")
    client = FakeClient.new(answers: [question_answer("Which is right?")])
    assert tidy(client)
    assert_nil tidy(client)
    assert_equal 1, client.requests.length
  end

  def test_the_merge_is_logged
    save("a")
    save("b")
    tidy(FakeClient.new(answers: [answer([merge_of(ids, "ab")])]))
    assert_includes LOGS.last, "2 facts"
  end
end
