require_relative "test_helper"
require_relative "../config"
require_relative "../chat_history"
require_relative "../command_context"

# A command turn: the AI ran a command tool (help, music, clear), so the stored history gets labels
class CommandTurnTest < Minitest::Test
  def test_command_turn_marks_user_message_and_keeps_labels
    history = []
    add_user_message(history, "Bach", 1, "skip")
    stored = mark_command_turn(history, ["[music: Skipped.]"], "Done!")
    assert history.last[:command]
    assert_equal "Done!\n[music: Skipped.]", stored
  end

  def test_trailing_space_of_the_answer_is_dropped_before_the_labels
    history = []
    add_user_message(history, "Bach", 1, "skip")
    assert_equal "Done!
[music: Skipped.]", mark_command_turn(history, ["[music: Skipped.]"], "Done!

")
  end

  def test_command_assistant_message_is_marked
    history = []
    add_assistant_message(history, "Done!", message_id: 7, command: true)
    assert_equal({ role: "assistant", content: "Done!", message_id: 7, command: true }, history.last)
  end

  def test_normal_assistant_message_has_no_command_key
    history = []
    add_assistant_message(history, "Hi", message_id: 7)
    refute history.last.key?(:command)
  end

  FakeEvent = Struct.new(:author, :server, :channel, :message, :bot)

  def test_command_context_has_the_discord_facts
    profile = Struct.new(:avatar_url).new("https://cake.png")
    event = FakeEvent.new(:author, :server, :channel, Struct.new(:id).new(42), Struct.new(:profile).new(profile))
    context = command_context(event, :music)
    assert_equal({ member: :author, server: :server, post_channel: :channel, music: :music,
                   request_message_id: 42, command_labels: [], avatar_url: "https://cake.png" }, context)
  end
end
