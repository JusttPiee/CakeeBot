require_relative "test_helper"
require_relative "../chat_history"

class ChatHistoryTest < Minitest::Test
  # Build a fake history with `count` turns (user message + assistant reply each)
  def make_history(count, text = "hi")
    history = []
    count.times do |i|
      add_user_message(history, "Bach", 123, "#{text} #{i}")
      add_assistant_message(history, "reply #{i}")
    end
    history
  end

  def test_user_message_has_nickname_and_id_prefix
    history = []
    add_user_message(history, "Bach", 123456789, "hello")
    assert_equal "user", history.last[:role]
    assert_equal "Bach (123456789): hello", history.last[:content]
  end

  def test_user_message_remembers_when_it_was_sent
    sent_at = Time.new(2026, 11, 1, 9, 0, 0)
    history = []
    add_user_message(history, "Bach", 123, "hello", sent_at)
    assert_equal sent_at, history.last[:time]
  end

  def test_each_channel_gets_its_own_history
    store = create_history_store
    add_user_message(store[1], "Bach", 123, "in channel 1")
    assert_equal 1, store[1].length
    assert_equal 0, store[2].length
  end

  def test_small_history_is_not_trimmed
    history = make_history(3)
    trim_history(history)
    assert_equal 6, history.length
  end

  def test_trims_to_message_limit
    history = make_history(30) # 60 messages
    trim_history(history)
    # Whole turns (2 messages here) are removed, so with an odd limit it can end 1 below it
    assert history.length <= MAX_HISTORY_MESSAGES
    assert history.length >= MAX_HISTORY_MESSAGES - 1
  end

  def test_keeps_the_newest_messages
    history = make_history(30)
    trim_history(history)
    assert_equal "reply 29", history.last[:content]
  end

  def test_trimmed_history_starts_on_a_user_message
    history = make_history(30)
    trim_history(history)
    assert_equal "user", history.first[:role]
  end

  def test_trims_by_token_budget
    long_text = "a" * 4_000 # about 1,000 tokens per message
    history = make_history(8, long_text) # 16 messages, under the message limit but way over 5,000 tokens
    trim_history(history)
    assert estimate_tokens(history) <= MAX_HISTORY_TOKENS
    assert_equal "user", history.first[:role]
  end

  def test_always_keeps_newest_turn_even_if_too_big
    history = []
    add_user_message(history, "Bach", 123, "a" * 30_000) # one message alone is over the budget
    trim_history(history)
    assert_equal 1, history.length
  end

  def test_never_cuts_a_turn_in_half
    # Turn with extra messages (like future tool calls): user, assistant, assistant
    history = make_history(20)
    history.insert(1, { role: "assistant", content: "extra step" })
    trim_history(history)
    assert_equal "user", history.first[:role]
    assert history.length <= MAX_HISTORY_MESSAGES
  end

  def test_remove_last_message_drops_unanswered_question
    history = make_history(2)
    add_user_message(history, "Bach", 123, "no answer")
    remove_last_message(history)
    assert_equal "reply 1", history.last[:content]
  end

  def test_format_for_openai_keeps_role_and_content
    history = []
    add_user_message(history, "Bach", 123, "hi", Time.new(2026, 11, 4, 14, 2, 30))
    add_assistant_message(history, "reply")
    assert_equal [{ role: "user", content: "[2026-11-04 14:02] Bach (123): hi" }, { role: "assistant", content: "reply" }],
                 format_history_for_openai(history)
  end

  def test_timestamp_does_not_change_between_requests
    history = []
    add_user_message(history, "Bach", 123, "I'm hungry", Time.new(2026, 11, 1, 9, 5, 0))
    assert_equal format_history_for_openai(history), format_history_for_openai(history)
  end

  def test_utc_times_are_shown_in_local_time
    sent_at = Time.new(2026, 11, 4, 14, 2, 0)
    history = []
    add_user_message(history, "Bach", 123, "hi", sent_at.getutc) # Discord gives UTC times
    assert_equal "[#{sent_at.strftime('%Y-%m-%d %H:%M')}] Bach (123): hi", format_history_for_openai(history).first[:content]
  end

  def test_bot_messages_get_no_timestamp
    history = []
    add_user_message(history, "Bach", 123, "hi")
    add_assistant_message(history, "Try pho!")
    assert_equal "Try pho!", format_history_for_openai(history).last[:content]
  end

  def test_messages_without_a_time_get_no_marker
    history = [{ role: "user", content: "Bach (123): hi" }]
    assert_equal "Bach (123): hi", format_history_for_openai(history).first[:content]
  end

  def test_entries_keep_discord_ids_but_openai_does_not_see_them
    history = []
    add_user_message(history, "Bach", 123, "hi", Time.now, message_id: 50)
    add_assistant_message(history, "yo", message_id: 51)
    assert_equal [50, 51], history.map { |m| m[:message_id] }
    assert_equal "123", history.first[:user_id]
    assert_equal "Bach", history.first[:name]
    assert_equal %i[role content], format_history_for_openai(history).first.keys
  end

  def test_last_message_id_skips_missing_ids
    assert_equal 50, last_message_id([{ message_id: 50 }, { message_id: nil }])
    assert_nil last_message_id([{ message_id: nil }])
  end

  def test_trim_to_custom_limits
    history = make_history(30) # 60 messages
    trim_history(history, 10, 100_000)
    assert history.length <= 10
  end
end
