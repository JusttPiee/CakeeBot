require_relative "test_helper"
require "json"
require "faraday"
require_relative "../config"
require_relative "../ai_channel_chat"
require_relative "../memory_tidy"

# The personality note is the bot's own guess from chat messages, so its owner stays in control:
# they can change or remove it, compaction respects that, and tidying fixes it when it disagrees with their facts.
class PersonalityControlTest < Minitest::Test
  NOW = Time.new(2026, 11, 7, 12, 0)
  BACH = { server_id: 1, channel_id: nil, requester_id: 123, requester_name: "Bach" }.freeze

  def setup
    clear_test_memory
    LOGS.clear
  end

  def note = read_user_note(1, 123)
  def guess(text = "Hush main.", description = "Hush main") = write_user_personality(1, 123, "Bach", text, description)
  def save(text) = append_remembered_fact(1, 123, "Bach", text, NOW)
  def tidy_answer(**fields) = { merges: [], question: "" }.merge(fields).to_json
  def logged?(*parts) = LOGS.any? { |line| parts.all? { |part| line.include?(part) } }

  # --- Removing it ---

  def test_a_person_can_remove_their_personality_note
    guess
    run_forget_my_personality({}, BACH)
    assert_equal "", note[:personality]
    assert_equal "", note[:description]
  end

  def test_removing_it_keeps_their_saved_facts
    guess
    save("likes pho")
    run_forget_my_personality({}, BACH)
    assert_equal ["likes pho"], personal_memory_items(1).map { |item| item[:text] }
  end

  def test_compaction_cant_write_it_again_after_removing
    guess
    run_forget_my_personality({}, BACH)
    write_user_personality(1, 123, "Bach", "Written again.", "again")
    assert_equal "", note[:personality]
  end

  def test_someone_with_no_note_yet_can_also_say_no
    run_forget_my_personality({}, BACH)
    write_user_personality(1, 123, "Bach", "Written.", "written")
    assert_equal "", note[:personality]
  end

  def test_saying_no_survives_saving_a_new_fact
    run_forget_my_personality({}, BACH)
    save("likes pho")
    write_user_personality(1, 123, "Bach", "Written.", "written")
    assert_equal "", note[:personality]
  end

  def test_removing_updates_the_index
    guess("Hush main.", "plays Hush")
    run_forget_my_personality({}, BACH)
    refute_includes read_memory_file(1, "MEMORY.md"), "plays Hush"
  end

  def test_removing_is_logged
    guess
    run_forget_my_personality({}, BACH)
    assert logged?("forget_my_personality", "Bach (123)")
  end

  # --- Changing it ---

  def test_a_person_can_change_their_personality_note
    guess
    run_update_my_personality({ "new_text" => "Chamber main.", "description" => "plays Chamber" }, BACH)
    assert_equal "Chamber main.", note[:personality]
    assert_equal "plays Chamber", note[:description]
  end

  def test_changing_it_turns_it_back_on
    run_forget_my_personality({}, BACH)
    run_update_my_personality({ "new_text" => "Chamber main.", "description" => "plays Chamber" }, BACH)
    write_user_personality(1, 123, "Bach", "Updated later.", "later")
    assert_equal "Updated later.", note[:personality]
  end

  def test_an_empty_change_is_refused
    guess
    assert_includes run_update_my_personality({ "new_text" => "  ", "description" => "x" }, BACH), "Error"
    assert_equal "Hush main.", note[:personality]
  end

  def test_a_too_long_change_is_refused
    guess
    long = "x" * (REMEMBER_FACT_MAX_CHARS + 1)
    assert_includes run_update_my_personality({ "new_text" => long, "description" => "x" }, BACH), "Error"
    assert_equal "Hush main.", note[:personality]
  end

  def test_the_tools_have_no_way_to_name_another_person
    [UPDATE_MY_PERSONALITY_DEFINITION, FORGET_MY_PERSONALITY_DEFINITION].each do |definition|
      refute definition[:parameters][:properties].key?(:user_id)
    end
  end

  def test_the_tools_are_available
    assert available_tools.key?("update_my_personality")
    assert available_tools.key?("forget_my_personality")
  end

  def test_there_is_no_memory_without_a_server
    assert_equal MEMORY_NOT_AVAILABLE, run_forget_my_personality({}, BACH.merge(server_id: nil))
    assert_equal MEMORY_NOT_AVAILABLE, run_update_my_personality({ "new_text" => "x" }, BACH.merge(server_id: nil))
  end

  # --- Tidying checks it against their facts ---

  def test_tidying_is_given_the_personality_note
    guess("Hush main.", "plays Hush")
    save("Is a Hush and Chamber main")
    client = FakeClient.new(answers: [tidy_answer])
    tidy_memory_if_needed(client, 1, 123)
    assert_includes client.requests.first[:input].to_s, "Hush main."
    assert_includes client.requests.first[:input].to_s, "plays Hush"
  end

  def test_tidying_can_correct_the_personality_note
    guess("Hush main.", "plays Hush")
    save("Is a Hush and Chamber main")
    tidy_memory_if_needed(FakeClient.new(answers: [tidy_answer(new_personality: "Hush and Chamber main.", new_description: "plays Hush and Chamber")]), 1, 123)
    assert_equal "Hush and Chamber main.", note[:personality]
    assert_equal "plays Hush and Chamber", note[:description]
  end

  def test_a_correction_is_logged_with_old_and_new_text
    guess("Hush main.", "plays Hush")
    save("Is a Hush and Chamber main")
    tidy_memory_if_needed(FakeClient.new(answers: [tidy_answer(new_personality: "Hush and Chamber main.", new_description: "")]), 1, 123)
    assert logged?("user 123", "Hush main.", "Hush and Chamber main.")
    refute logged?("no changes")
  end

  def test_an_empty_correction_changes_nothing
    guess("Hush main.", "plays Hush")
    save("Is a Hush and Chamber main")
    tidy_memory_if_needed(FakeClient.new(answers: [tidy_answer(new_personality: "", new_description: "")]), 1, 123)
    assert_equal "Hush main.", note[:personality]
    assert_equal "plays Hush", note[:description]
  end

  def test_a_correction_cant_create_a_note_that_doesnt_exist
    save("likes pho")
    save("plays Chamber")
    tidy_memory_if_needed(FakeClient.new(answers: [tidy_answer(new_personality: "Made up.", new_description: "made up")]), 1, 123)
    assert_equal "", note[:personality]
    assert_equal "", note[:description]
  end

  def test_correcting_the_note_keeps_the_facts
    guess
    save("Is a Hush and Chamber main")
    tidy_memory_if_needed(FakeClient.new(answers: [tidy_answer(new_personality: "Hush and Chamber main.")]), 1, 123)
    assert_equal ["Is a Hush and Chamber main"], personal_memory_items(1).map { |item| item[:text] }
  end

  def test_one_fact_and_a_personality_note_are_enough_to_check
    guess
    save("Is a Chamber main")
    client = FakeClient.new(answers: [tidy_answer])
    tidy_memory_if_needed(client, 1, 123)
    assert_equal 1, client.requests.length
  end

  def test_a_new_personality_note_means_checking_again
    guess
    save("Is a Chamber main")
    client = FakeClient.new(answers: [tidy_answer])
    tidy_memory_if_needed(client, 1, 123)
    guess("Changed by compaction.", "changed")
    tidy_memory_if_needed(client, 1, 123)
    assert_equal 2, client.requests.length
  end

  def test_a_new_personality_note_is_tidied_again_at_startup
    guess
    save("Is a Chamber main")
    tidy_all_memory(FakeClient.new(answers: [tidy_answer]))
    guess("Changed by compaction.", "changed")
    client = FakeClient.new(answers: [tidy_answer])
    tidy_all_memory(client)
    assert_equal 1, client.requests.length
  end

  def test_a_corrected_note_is_not_checked_again
    guess
    save("Is a Chamber main")
    client = FakeClient.new(answers: [tidy_answer(new_personality: "Chamber main.")])
    2.times { tidy_memory_if_needed(client, 1, 123) }
    assert_equal 1, client.requests.length
  end

  # --- The rules ---

  def test_the_chat_rules_explain_personality_notes
    rules = read_prompt("memory_rules")
    assert_includes rules, "forget_my_personality"
    assert_includes rules, "update_my_personality"
    assert_includes rules, "your own guess"
  end

  def test_the_tidy_prompt_says_their_own_facts_win
    prompt = read_prompt("tidy_memory")
    assert_includes prompt, "new_personality"
    assert_includes prompt, "their facts win"
  end
end
