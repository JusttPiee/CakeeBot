require_relative "test_helper"
require_relative "fake_discord"
require_relative "../config"
require_relative "../tool_list"
require_relative "../forget_me"
require_relative "../ai_chat" # CAPABILITIES and MEMORY_RULES

# !forgetme removes everything about one person, and stops new personality notes about them
class ForgetMeTest < Minitest::Test
  SERVER = HistoryServer.new(1, "Test Server", [], nil)
  BACH = CommandUser.new(123, "Bach", false)

  def setup
    clear_test_memory
    LOGS.clear
  end

  def save_bach_memories
    change_user_personality(1, 123, "Bach", "Loves Valorant", "gamer")
    append_remembered_fact(1, 123, "Bach", "call me Boss")
    append_remembered_fact(1, 123, "Bach", "likes pho")
    append_general_note(1, 123, "Bach", 456, "Pie", "is bad at Valorant") # Bach about Pie
    append_general_note(1, 456, "Pie", 123, "Bach", "never sleeps") # Pie about Bach
    append_remembered_fact(1, 456, "Pie", "call 123 'the Boss' when talking to me") # Pie's fact that names Bach's id
    append_remembered_fact(1, 456, "Pie", "likes cats") # nothing to do with Bach
    append_general_note(1, 456, "Pie", 789, "Minh", "is funny") # nothing to do with Bach
    with_server_memory_lock(1) { rebuild_memory_index(1) }
  end

  def test_preview_counts_what_would_be_removed
    save_bach_memories
    assert_equal({ facts: 2, personality: true, shared: 3 }, forget_me_preview(1, 123))
  end

  def test_preview_of_someone_with_nothing_saved
    assert_equal({ facts: 0, personality: false, shared: 0 }, forget_me_preview(1, 123))
  end

  def test_removes_everything_about_them
    save_bach_memories
    forget_user(1, 123)
    note = read_user_note(1, 123)
    assert_equal "", note[:personality]
    assert_empty note[:remembered]
    assert_equal "", note[:name]
    general = read_memory_file(1, "general.md")
    refute_includes general, "Valorant"
    refute_includes general, "never sleeps"
    assert_equal ["likes cats"], read_user_note(1, 456)[:remembered].map { |fact| fact.sub(/\A\[[^\]]*\] /, "") }
  end

  def test_other_peoples_unrelated_memories_stay
    save_bach_memories
    forget_user(1, 123)
    assert_includes read_memory_file(1, "general.md"), "is funny"
    assert_includes read_user_note(1, 456)[:remembered].last, "likes cats"
  end

  def test_the_index_no_longer_shows_them
    save_bach_memories
    forget_user(1, 123)
    index = read_memory_file(1, "MEMORY.md")
    refute_includes index, "users/123.md"
    refute_includes index, "Bach"
    assert_includes index, "likes cats"
  end

  def test_compaction_cant_write_a_new_personality_note
    forget_user(1, 123)
    write_user_personality(1, 123, "Bach", "Plays a lot of Valorant", "gamer")
    assert_equal "", read_user_note(1, 123)[:personality]
  end

  def test_they_can_still_ask_cake_to_remember_things
    forget_user(1, 123)
    run_tool("remember_about_me", '{"fact":"likes pho"}', { server_id: 1, requester_id: 123, requester_name: "Bach" })
    note = read_user_note(1, 123)
    assert_equal 1, note[:remembered].length
    assert note[:personality_off] # and the personality note stays off
  end

  def test_tidying_forgets_them_too
    update_tidy_state(1, 123, channel: 555, asked_questions: ["Is it Boss or Chief?"])
    update_tidy_state(1, 456, channel: 777)
    forget_user(1, 123)
    assert_equal({}, tidy_state_of(1, 123))
    assert_equal 777, tidy_state_of(1, 456)["channel"]
  end

  def test_works_when_nothing_was_saved
    forget_user(1, 123)
    assert read_user_note(1, 123)[:personality_off]
  end

  # --- the command ---

  def test_command_without_confirm_only_shows_what_would_be_removed
    save_bach_memories
    event = CommandEvent.new(SERVER, BACH)
    forget_me_command(event, nil)
    assert_includes event.responses.last, "things you asked me to remember: 2"
    assert_includes event.responses.last, "!forgetme confirm"
    assert_equal 2, read_user_note(1, 123)[:remembered].length # nothing deleted yet
  end

  def test_command_with_confirm_removes_it
    save_bach_memories
    event = CommandEvent.new(SERVER, BACH)
    forget_me_command(event, "CONFIRM")
    assert_includes event.responses.last, "I forgot everything"
    assert_empty read_user_note(1, 123)[:remembered]
  end

  def test_command_only_works_in_a_server
    event = CommandEvent.new(nil, BACH)
    forget_me_command(event, "confirm")
    assert_includes event.responses.last, "only works in a server"
  end

  def test_the_bot_knows_about_the_command
    assert_includes CAPABILITIES, "!forgetme"
    assert_includes MEMORY_RULES, "!forgetme"
  end
end
