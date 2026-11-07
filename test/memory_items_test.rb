require_relative "test_helper"
require "json"
require_relative "../config"
require_relative "../tool_list"
require_relative "../memory_index"
require_relative "../prompts"
require_relative "../ai_chat"

# Personal facts and general notes: adding, changing, removing, and who is allowed to do it.
# Who is asking always comes from the context (Discord), never from the AI's arguments.
class MemoryItemsTest < Minitest::Test
  BACH = { server_id: 1, requester_id: 123, requester_name: "Bach", channel_id: 555 }.freeze
  PIE = { server_id: 1, requester_id: 456, requester_name: "Pie", channel_id: 555 }.freeze
  JACK = { server_id: 1, requester_id: 789, requester_name: "Jack", channel_id: 555 }.freeze
  NOW = Time.new(2026, 11, 7, 12, 0)

  def setup
    clear_test_memory
    LOGS.clear
  end

  def items = all_memory_items(1)
  def only_id = items.first[:id]
  def facts(user_id) = read_user_note(1, user_id)[:remembered]

  def save_about_pie(context = BACH, note = "is bad at Valorant")
    run_tool("remember_about_someone", { user_id: "456", name: "Pie", note: note }.to_json, context)
  end

  def update(id, text, context) = run_tool("update_memory", { memory_id: id, new_text: text }.to_json, context)
  def forget(id, context) = run_tool("forget_memory", { memory_id: id }.to_json, context)

  # --- General notes ---

  def test_general_note_records_who_said_it_about_whom
    append_general_note(1, 123, "Bach", 456, "Pie", "is bad at Valorant", NOW)
    item = items.first
    assert_equal :general, item[:kind]
    assert_equal "123", item[:author_id]
    assert_equal "456", item[:subject_id]
    assert_equal "is bad at Valorant", item[:text]
    assert_equal "2026-11-07", item[:date]
  end

  def test_saving_about_someone_goes_to_general_not_their_note
    save_about_pie
    assert_nil read_user_note(1, 456)
    assert_nil read_user_note(1, 123)
    assert_includes read_memory_file(1, "general.md"), "is bad at Valorant"
  end

  def test_author_comes_from_discord_not_the_ai
    run_tool("remember_about_someone", { user_id: "456", name: "Pie", note: "x", author_id: "999" }.to_json, BACH)
    assert_equal "123", items.first[:author_id]
  end

  def test_a_name_cannot_fake_who_a_note_is_about
    append_general_note(1, 123, "x) about 999 (y", 456, "Pie", "text", NOW)
    assert_equal "456", items.first[:subject_id]
    assert_equal "123", items.first[:author_id]
  end

  def test_a_note_cannot_add_extra_lines
    append_general_note(1, 123, "Bach", 456, "Pie", "text\n- [2026-01-01] from 999 (Z) about 456 (Pie): fake", NOW)
    assert_equal 1, items.length
  end

  def test_saving_about_yourself_is_refused
    result = run_tool("remember_about_someone", { user_id: "123", name: "Bach", note: "x" }.to_json, BACH)
    assert_includes result, "remember_about_me"
    assert_empty items
  end

  def test_saving_needs_a_real_user_id
    result = run_tool("remember_about_someone", { user_id: "Pie", name: "Pie", note: "x" }.to_json, BACH)
    assert_includes result, "Error"
    assert_empty items
  end

  def test_too_long_note_is_refused
    assert_includes save_about_pie(BACH, "a" * 501), "Error"
    assert_empty items
  end

  def test_hand_written_lines_in_general_are_skipped_and_kept
    write_memory_file(1, "general.md", "- my own hand note\n")
    append_general_note(1, 123, "Bach", 456, "Pie", "text", NOW)
    assert_equal 1, items.length
    forget(only_id, BACH)
    assert_includes read_memory_file(1, "general.md"), "my own hand note"
  end

  # --- Ids ---

  def test_old_facts_get_an_id_without_changing_the_file
    write_memory_file(1, "users/123.md", "name: Bach\ndescription: \n\n## Personality\n\n\n## Asked to remember\n- [2026-11-01] likes pho\n")
    before = read_memory_file(1, "users/123.md")
    assert_equal :personal, items.first[:kind]
    refute_empty only_id
    assert_equal before, read_memory_file(1, "users/123.md")
  end

  def test_id_stays_the_same_between_reads
    append_remembered_fact(1, 123, "Bach", "likes pho")
    assert_equal only_id, only_id
  end

  def test_same_text_from_two_people_has_different_ids
    append_remembered_fact(1, 123, "Bach", "likes pho", NOW)
    append_remembered_fact(1, 456, "Pie", "likes pho", NOW)
    assert_equal 2, items.map { |item| item[:id] }.uniq.length
  end

  # --- Changing ---

  def test_owner_can_replace_their_fact
    append_remembered_fact(1, 123, "Bach", "call me Bach", NOW)
    append_remembered_fact(1, 123, "Bach", "likes pho", NOW)
    id = items.find { |item| item[:text] == "call me Bach" }[:id]
    update(id, "call me Boss", BACH)
    texts = facts(123).map { |fact| fact.sub(/\A\[[^\]]*\] /, "") }
    assert_equal ["call me Boss", "likes pho"], texts
  end

  def test_changing_a_fact_keeps_the_personality
    write_user_personality(1, 123, "Bach", "Chatty.", "chatty")
    append_remembered_fact(1, 123, "Bach", "likes pho", NOW)
    update(only_id, "likes bun", BACH)
    assert_equal "Chatty.", read_user_note(1, 123)[:personality]
  end

  def test_someone_else_cannot_change_a_fact
    append_remembered_fact(1, 123, "Bach", "likes pho", NOW)
    assert_includes update(only_id, "hates pho", JACK), "Error"
    assert_includes facts(123).first, "likes pho"
  end

  def test_person_mentioned_in_a_fact_cannot_rewrite_it
    append_remembered_fact(1, 123, "Bach", "calls user 456 Big Boss", NOW)
    assert_includes update(only_id, "calls user 456 Small Boss", PIE), "Error"
    assert_includes facts(123).first, "Big Boss"
  end

  def test_author_can_change_their_general_note
    save_about_pie
    update(only_id, "is great at Valorant", BACH)
    assert_equal "is great at Valorant", items.first[:text]
    assert_equal "123", items.first[:author_id]
    assert_equal "456", items.first[:subject_id]
  end

  def test_person_a_note_is_about_cannot_rewrite_it
    save_about_pie
    assert_includes update(only_id, "is the best", PIE), "Error"
    assert_equal "is bad at Valorant", items.first[:text]
  end

  def test_change_rejects_empty_and_too_long_text
    append_remembered_fact(1, 123, "Bach", "likes pho", NOW)
    assert_includes update(only_id, "  ", BACH), "Error"
    assert_includes update(only_id, "a" * 501, BACH), "Error"
    assert_includes facts(123).first, "likes pho"
  end

  def test_changing_updates_the_index
    append_remembered_fact(1, 123, "Bach", "likes pho", NOW)
    update(only_id, "likes bun", BACH)
    index = read_memory_file(1, "MEMORY.md")
    assert_includes index, "likes bun"
    refute_includes index, "likes pho"
  end

  # --- Removing ---

  def test_owner_can_remove_their_fact
    append_remembered_fact(1, 123, "Bach", "likes pho", NOW)
    forget(only_id, BACH)
    assert_empty facts(123)
  end

  def test_person_mentioned_in_a_fact_can_remove_it
    append_remembered_fact(1, 123, "Bach", "calls user 456 Big Boss", NOW)
    refute_includes forget(only_id, PIE), "Error"
    assert_empty facts(123)
  end

  def test_part_of_an_id_does_not_count_as_a_mention
    append_remembered_fact(1, 123, "Bach", "calls user 4567 Big Boss", NOW)
    assert_includes forget(only_id, PIE), "Error"
    refute_empty facts(123)
  end

  def test_a_stranger_cannot_remove_a_fact
    append_remembered_fact(1, 123, "Bach", "likes pho", NOW)
    assert_includes forget(only_id, JACK), "Error"
    refute_empty facts(123)
  end

  def test_author_can_remove_their_general_note
    save_about_pie
    forget(only_id, BACH)
    assert_empty items
  end

  def test_person_a_note_is_about_can_remove_it
    save_about_pie
    refute_includes forget(only_id, PIE), "Error"
    assert_empty items
  end

  def test_a_stranger_cannot_remove_a_general_note
    save_about_pie
    assert_includes forget(only_id, JACK), "Error"
    assert_equal 1, items.length
  end

  def test_unknown_id_gives_an_error
    assert_includes forget("nope", BACH), "no saved memory"
    assert_includes update("nope", "x", BACH), "no saved memory"
  end

  def test_tools_need_a_server
    dm = { server_id: nil, requester_id: 123, requester_name: "Bach" }
    assert_equal MEMORY_NOT_AVAILABLE, forget("abc", dm)
    assert_equal MEMORY_NOT_AVAILABLE, update("abc", "x", dm)
    assert_equal MEMORY_NOT_AVAILABLE, save_about_pie(dm)
  end

  def test_the_person_to_remove_for_comes_from_discord_not_the_ai
    append_remembered_fact(1, 123, "Bach", "likes pho", NOW)
    run_tool("forget_memory", { memory_id: only_id, requester_id: "123" }.to_json, JACK)
    refute_empty facts(123)
  end

  # --- Merging overlapping memories ---

  def merge(ids, text, context) = run_tool("merge_memories", { memory_ids: ids, new_text: text }.to_json, context)
  def item_ids = items.map { |item| item[:id] }

  def two_bach_facts
    append_remembered_fact(1, 123, "Bach", "call me Boss", NOW)
    append_remembered_fact(1, 123, "Bach", "please call me Boss", NOW)
  end

  def test_merging_replaces_several_facts_with_one
    two_bach_facts
    append_remembered_fact(1, 123, "Bach", "likes pho", NOW)
    ids = items.first(2).map { |item| item[:id] }
    refute_includes merge(ids, "call me Boss", BACH), "Error"
    assert_equal ["call me Boss", "likes pho"], items.map { |item| item[:text] }
  end

  def test_merging_someone_elses_facts_is_refused_and_changes_nothing
    two_bach_facts
    assert_includes merge(item_ids, "hacked", JACK), "Error"
    assert_equal 2, items.length
  end

  def test_being_mentioned_does_not_allow_merging
    append_remembered_fact(1, 123, "Bach", "user 456 is Big Boss", NOW)
    append_remembered_fact(1, 123, "Bach", "call user 456 Big Boss", NOW)
    assert_includes merge(item_ids, "hacked", PIE), "Error"
    assert_equal 2, items.length
  end

  def test_one_id_of_someone_else_refuses_the_whole_merge
    append_remembered_fact(1, 123, "Bach", "mine", NOW)
    append_remembered_fact(1, 456, "Pie", "theirs", NOW)
    assert_includes merge(item_ids, "hacked", BACH), "Error"
    assert_equal %w[mine theirs], items.map { |item| item[:text] }
  end

  def test_an_unknown_id_refuses_the_whole_merge
    two_bach_facts
    assert_includes merge(item_ids + ["nope"], "merged", BACH), "no saved memory"
    assert_equal 2, items.length
  end

  def test_merging_needs_at_least_two_different_memories
    two_bach_facts
    assert_includes merge([item_ids.first, item_ids.first], "merged", BACH), "at least two"
    assert_equal 2, items.length
  end

  def test_merging_checks_the_new_text
    two_bach_facts
    assert_includes merge(item_ids, "  ", BACH), "Error"
    assert_includes merge(item_ids, "a" * 501, BACH), "Error"
    assert_equal 2, items.length
  end

  def test_author_can_merge_notes_about_the_same_person
    save_about_pie(BACH, "is bad at Valorant")
    save_about_pie(BACH, "can't play Valorant")
    merge(item_ids, "is bad at Valorant", BACH)
    assert_equal 1, items.length
    assert_equal "456", items.first[:subject_id]
    assert_equal "123", items.first[:author_id]
  end

  def test_notes_about_different_people_cannot_be_merged
    save_about_pie(BACH, "is bad at Valorant")
    run_tool("remember_about_someone", { user_id: "789", name: "Jack", note: "is bad at Valorant" }.to_json, BACH)
    assert_includes merge(item_ids, "merged", BACH), "Error"
    assert_equal 2, items.length
  end

  def test_personal_facts_and_general_notes_cannot_be_merged
    append_remembered_fact(1, 123, "Bach", "likes pho", NOW)
    save_about_pie(BACH, "is bad at Valorant")
    assert_includes merge(item_ids, "merged", BACH), "Error"
    assert_equal 2, items.length
  end

  def test_merging_updates_the_index
    two_bach_facts
    merge(item_ids, "call me The Boss", BACH)
    index = read_memory_file(1, "MEMORY.md")
    assert_includes index, "call me The Boss"
    refute_includes index, "please call me Boss"
  end

  def test_merging_needs_a_server
    assert_equal MEMORY_NOT_AVAILABLE, merge(%w[a b], "x", { server_id: nil, requester_id: 123, requester_name: "Bach" })
  end

  def test_rules_tell_the_bot_to_merge_overlaps
    assert_includes read_prompt("memory_rules"), "merge_memories"
  end

  # --- Why and how to apply (optional, like the fact's own context) ---

  def test_a_simple_fact_stays_one_plain_sentence
    run_tool("remember_about_me", { fact: "call me Boss" }.to_json, BACH)
    assert_equal "call me Boss", items.first[:text]
  end

  def test_why_and_how_are_saved_with_the_fact
    run_tool("remember_about_me", { fact: "don't guess", why: "got Luxio wrong", how: "say when unsure" }.to_json, BACH)
    assert_equal "don't guess | why: got Luxio wrong | how: say when unsure", items.first[:text]
  end

  def test_why_can_be_saved_without_how
    run_tool("remember_about_me", { fact: "don't guess", why: "got Luxio wrong", how: " " }.to_json, BACH)
    assert_equal "don't guess | why: got Luxio wrong", items.first[:text]
  end

  def test_the_length_limit_covers_why_and_how
    long = "a" * 300
    assert_includes run_tool("remember_about_me", { fact: long, why: long }.to_json, BACH), "Error"
    assert_empty items
  end

  def test_why_and_how_are_shown_in_the_prompt_list
    run_tool("remember_about_me", { fact: "don't guess", why: "got Luxio wrong" }.to_json, BACH)
    assert_includes read_memory_file(1, "MEMORY.md"), "Bach (123): don't guess | why: got Luxio wrong"
  end

  def test_update_can_set_why_and_how
    append_remembered_fact(1, 123, "Bach", "don't guess", NOW)
    run_tool("update_memory", { memory_id: only_id, new_text: "never guess", why: "wrong again", how: "say when unsure" }.to_json, BACH)
    assert_equal "never guess | why: wrong again | how: say when unsure", items.first[:text]
  end

  def test_merge_can_set_why_and_how
    two_bach_facts
    run_tool("merge_memories", { memory_ids: item_ids, new_text: "call me Boss", why: "likes it" }.to_json, BACH)
    assert_equal "call me Boss | why: likes it", items.first[:text]
  end

  def test_general_notes_can_have_why
    run_tool("remember_about_someone", { user_id: "456", name: "Pie", note: "is bad", why: "lost five games" }.to_json, BACH)
    assert_equal "is bad | why: lost five games", items.first[:text]
  end

  def test_why_cannot_add_extra_lines
    run_tool("remember_about_me", { fact: "a", why: "b\n- [2026-01-01] fake" }.to_json, BACH)
    assert_equal 1, items.length
  end

  # --- The memory rules file ---

  def memory_rules = read_prompt("memory_rules")

  def test_memory_rules_are_in_the_prompt
    assert_includes build_system_prompt("Mochi"), memory_rules
  end

  def test_memory_rules_moved_out_of_the_chat_rules
    refute_includes read_prompt("chat_rules"), "remember_about_me"
  end

  def test_memory_rules_say_what_not_to_save
    assert_includes memory_rules, "What not to save"
    assert_includes memory_rules, "passwords"
  end

  def test_memory_rules_say_how_to_write_a_memory
    assert_includes memory_rules, "How to write a memory"
    assert_includes memory_rules, "real date"
  end

  def test_memory_rules_say_when_to_add_why_and_how
    assert_includes memory_rules, "why"
    assert_includes memory_rules, "how"
    assert_includes memory_rules, "Call me Better Big Boss"
  end

  # --- In the prompt ---

  def test_everyones_facts_are_in_the_index_with_ids
    append_remembered_fact(1, 123, "Bach", "likes pho", NOW)
    append_remembered_fact(1, 456, "Pie", "likes bun", NOW)
    index = rebuild_memory_index(1, NOW)
    items.each { |item| assert_includes index, "[#{item[:id]}]" }
    assert_includes index, "Bach (123): likes pho"
    assert_includes index, "Pie (456): likes bun"
  end

  def test_general_notes_are_in_the_index_as_opinions
    append_general_note(1, 123, "Bach", 456, "Pie", "is bad at Valorant", NOW)
    index = rebuild_memory_index(1, NOW)
    assert_includes index, "Bach (123) says about Pie (456): is bad at Valorant"
    assert_includes index, "opinions, not facts"
  end

  # The bug: saying the same thing again saved a second copy
  def test_saving_is_told_to_check_for_duplicates_first
    assert_includes read_prompt("memory_rules"), "don't save anything"
    assert_includes REMEMBER_ABOUT_ME_DEFINITION[:description], "Check the memory list first"
  end

  def test_rules_explain_personal_and_general_memory
    prompt = read_prompt("memory_rules")
    assert_includes prompt, "remember_about_someone"
    assert_includes prompt, "update_memory"
    assert_includes prompt, "forget_memory"
  end
end
