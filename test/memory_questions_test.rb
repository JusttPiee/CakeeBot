require_relative "test_helper"
require "json"
require "faraday"
require_relative "../config"
require_relative "../ai_channel_chat"
require_relative "../memory_tidy"

# When facts differ and it isn't clear which is right, the bot asks by itself, without anyone asking it to.
class MemoryQuestionsTest < Minitest::Test
  NOW = Time.new(2026, 11, 7, 12, 0)
  QUESTION = "Do you prefer Better Big Boss or Bloo?".freeze

  class FakeChannel
    attr_reader :sent

    def initialize(error: nil)
      @sent = []
      @error = error
    end

    def id = 555

    def send_message(text)
      raise @error if @error

      @sent << text
    end
  end

  class FakeBot
    attr_reader :asked_for

    def initialize(channel) = @channel = channel

    def channel(id)
      @asked_for = id
      @channel
    end
  end

  def setup
    clear_test_memory
    LOGS.clear
    @channel = FakeChannel.new
    @bot = FakeBot.new(@channel)
  end

  def save(text, user_id = 123, name = "Bach") = append_remembered_fact(1, user_id, name, text, NOW)
  def asks(question = QUESTION) = FakeClient.new(answers: [{ merges: [], question: question }.to_json])
  def quiet = asks("")

  # --- Asking at startup ---

  def test_the_bot_pings_the_person_in_their_last_channel
    save("call me Boss")
    remember_last_channel(1, 123, 555)
    tidy_all_memory(asks, @bot)
    assert_equal 555, @bot.asked_for
    assert_equal ["<@123> #{QUESTION}"], @channel.sent
  end

  def test_no_question_means_no_message
    save("call me Boss")
    remember_last_channel(1, 123, 555)
    tidy_all_memory(quiet, @bot)
    assert_empty @channel.sent
  end

  def test_the_same_question_is_not_sent_again_after_a_restart
    save("call me Boss")
    remember_last_channel(1, 123, 555)
    2.times { tidy_all_memory(asks, @bot) }
    assert_equal 1, @channel.sent.length
  end

  def test_a_changed_note_can_ask_again
    save("call me Boss")
    remember_last_channel(1, 123, 555)
    tidy_all_memory(asks, @bot)
    save("call me Chief")
    tidy_all_memory(asks, @bot)
    assert_equal 2, @channel.sent.length
  end

  def test_unknown_channel_waits_for_the_next_message
    save("call me Boss")
    tidy_all_memory(asks, @bot)
    assert_empty @channel.sent
    assert_equal QUESTION, take_pending_question(1, 123)
  end

  def test_a_failed_send_keeps_the_question_and_logs
    save("call me Boss")
    remember_last_channel(1, 123, 555)
    tidy_all_memory(asks, FakeBot.new(FakeChannel.new(error: IOError.new("no permission"))))
    assert_equal QUESTION, take_pending_question(1, 123)
    assert(LOGS.any? { |line| line.include?("IOError") })
  end

  def test_a_deleted_channel_keeps_the_question
    save("call me Boss")
    remember_last_channel(1, 123, 555)
    tidy_all_memory(asks, FakeBot.new(nil))
    assert_equal QUESTION, take_pending_question(1, 123)
  end

  def test_a_kept_question_is_sent_at_the_next_startup
    save("call me Boss")
    remember_last_channel(1, 123, 555)
    tidy_all_memory(asks, FakeBot.new(FakeChannel.new(error: IOError.new("no permission"))))
    tidy_all_memory(FakeClient.new, @bot)
    assert_equal ["<@123> #{QUESTION}"], @channel.sent
    assert_nil take_pending_question(1, 123)
  end

  def test_a_question_from_startup_is_not_asked_again_in_chat
    save("call me Boss")
    remember_last_channel(1, 123, 555)
    tidy_all_memory(asks, @bot)
    client = asks
    assert_nil tidy_memory_if_needed(client, 1, 123)
    assert_empty client.requests
  end

  # --- A waiting question ---

  def test_a_waiting_question_is_only_asked_once
    save_pending_question(1, 123, QUESTION)
    assert_equal QUESTION, take_pending_question(1, 123)
    assert_nil take_pending_question(1, 123)
  end

  def test_questions_are_per_person
    save_pending_question(1, 123, QUESTION)
    assert_nil take_pending_question(1, 456)
    assert_equal QUESTION, take_pending_question(1, 123)
  end

  # --- The last channel ---

  def test_the_newest_channel_wins
    remember_last_channel(1, 123, 555)
    remember_last_channel(1, 123, 666)
    assert_equal 666, last_channel_of(1, 123)
  end

  def test_an_unchanged_channel_does_not_write_the_file
    remember_last_channel(1, 123, 555)
    path = File.join(server_memory_dir(1), "tidy_state.md")
    File.write(path, File.read(path) + "\n")
    before = File.read(path)
    remember_last_channel(1, 123, 555)
    assert_equal before, File.read(path)
  end

  def test_a_broken_state_file_is_treated_as_empty
    write_memory_file(1, "tidy_state.md", "not json")
    assert_nil last_channel_of(1, 123)
    remember_last_channel(1, 123, 555)
    assert_equal 555, last_channel_of(1, 123)
  end

  # --- Starting once ---

  def test_startup_tidy_only_runs_once_even_if_discord_reconnects
    save("call me Boss")
    MEMORY_TIDY_STARTED.make_false
    client = quiet
    2.times { start_memory_tidy_once(client, @bot)&.join }
    assert_equal 1, client.requests.length
  end

  # --- The instructions ---

  def test_the_prompt_says_to_ask_instead_of_guessing
    prompt = read_prompt("tidy_memory")
    assert_includes prompt, "don't merge them"
    assert_includes prompt, "same date"
  end
end
