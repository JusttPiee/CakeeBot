require_relative "test_helper"
require "json"
require "faraday"
require_relative "../config"
require_relative "../ai_channel_chat"

# Pretend Discord event for a message in an AI channel (only what answer_ai_channel_message uses).
# Server 1, channel 555, author Bach (123). reply! returns a message whose id counts up from 1.
class FakeAiEvent
  FakeUser = Struct.new(:id, :display_name)
  FakeBotMember = Struct.new(:display_name)
  FakeServer = Struct.new(:id, :bot)
  FakeChannel = Struct.new(:id) do
    def start_typing = nil
  end

  attr_reader :sent, :author, :server, :channel, :id

  def initialize(text, message_id: 500)
    @text = text
    @id = message_id
    @sent = []
    @author = FakeUser.new(123, "Bach")
    @server = FakeServer.new(1, FakeBotMember.new("Cake"))
    @channel = FakeChannel.new(555)
  end

  def message = self # event.message.id / .content / .reply! land here
  def content = @text

  def reply!(text, mention_user:)
    @sent << { text: text, ping: mention_user }
    Struct.new(:id).new(@sent.length)
  end
end

class AiChannelChatTest < Minitest::Test
  def setup
    clear_test_memory
    LOGS.clear
  end

  def test_reply_is_saved_with_its_discord_id
    history = []
    answer_ai_channel_message(FakeAiEvent.new("hello", message_id: 500), FakeClient.new(answers: ["Hi!"]), history)
    assert_equal [500, 1], history.map { |m| m[:message_id] }
  end

  def test_compaction_runs_when_history_is_full
    history = []
    44.times { |i| add_user_message(history, "Bach", 123, "m#{i}", Time.now, message_id: i + 1) }
    client = FakeClient.new(answers: ["Hi!", { summary: "s", events: [], user_personalities: [] }.to_json])
    answer_ai_channel_message(FakeAiEvent.new("one more", message_id: 99), client, history)
    assert_equal 2, client.requests.length
    assert history.length <= COMPACT_TARGET_MESSAGES
  end

  def test_no_compaction_when_history_is_small
    client = FakeClient.new(answers: ["Hi!"])
    answer_ai_channel_message(FakeAiEvent.new("hello"), client, [])
    assert_equal 1, client.requests.length
  end

  def test_hard_ceiling_cuts_before_sending
    history = []
    80.times { |i| add_user_message(history, "Bach", 123, "m#{i}", Time.now, message_id: i + 1) }
    client = FakeClient.new(error: Faraday::ConnectionFailed.new("down"))
    answer_ai_channel_message(FakeAiEvent.new("one more"), client, history)
    assert history.length <= HARD_MAX_HISTORY_MESSAGES
  end

  def test_failed_answer_removes_the_question
    history = []
    event = FakeAiEvent.new("hello")
    answer_ai_channel_message(event, FakeClient.new(error: Faraday::ConnectionFailed.new("x")), history)
    assert_equal [], history
    assert_includes event.sent.last[:text], "unavailable"
  end

  def test_remember_request_writes_the_senders_note
    call = { "type" => "function_call", "call_id" => "c1", "name" => "remember_about_me",
             "arguments" => '{"fact":"hates anime"}' }
    client = FakeClient.new(answers: [{ tool_calls: [call] }, "Got it"])
    answer_ai_channel_message(FakeAiEvent.new("remember I hate anime"), client, [])
    assert_equal 1, read_user_note(1, 123)[:remembered].length
  end
end
