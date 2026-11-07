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
  FakeServer = Struct.new(:id, :bot, :name)
  FakeChannel = Struct.new(:id, :name) do
    def start_typing = nil
  end
  FakeBot = Struct.new(:profile)
  FakeProfile = Struct.new(:id)

  attr_reader :sent, :author, :server, :channel, :id

  def initialize(text, message_id: 500, bot_name: "Cake")
    @text = text
    @id = message_id
    @sent = []
    @author = FakeUser.new(123, "Bach")
    @server = FakeServer.new(1, FakeBotMember.new(bot_name), "My Server")
    @channel = FakeChannel.new(555, "general")
    @attachments = []
  end

  attr_accessor :attachments, :referenced_message

  def bot = FakeBot.new(FakeProfile.new(999))
  def reply? = !referenced_message.nil?
  def message = self # event.message.id / .content / .reply! / .attachments land here
  def content = @text

  def reply!(text, mention_user:)
    @sent << { text: text, ping: mention_user }
    Struct.new(:id).new(@sent.length)
  end
end

class AiChannelChatTest < Minitest::Test
  FakeUser = FakeAiEvent::FakeUser

  def setup
    clear_test_memory
    LOGS.clear
  end

  def test_reply_is_saved_with_its_discord_id
    history = []
    answer_ai_channel_message(FakeAiEvent.new("hello", message_id: 500), FakeClient.new(answers: ["Hi!"]), history)
    assert_equal [500, 1], history.map { |m| m[:message_id] }
  end

  FakeAttachment = Struct.new(:id, :filename, :proxy_url, :url, :width, :height, :content_type) do
    def image? = true
  end

  def cat_picture
    FakeAttachment.new(42, "cat.png", "https://media.discordapp.net/cat.png", "https://cdn.discordapp.com/cat.png", 800, 600, "image/png")
  end

  def test_posted_image_goes_into_the_history_as_a_marker
    history = []
    event = FakeAiEvent.new("look")
    event.attachments = [cat_picture]
    answer_ai_channel_message(event, FakeClient.new(answers: ["Hi!"]), history)
    assert_includes history.first[:content], "look [image 42: cat.png]"
    assert_equal "42", history.first[:images].first[:id]
  end

  def test_reply_to_an_image_can_open_that_image
    history = []
    event = FakeAiEvent.new("what is this")
    poster = FakeUser.new(777, "b")
    event.referenced_message = Struct.new(:content, :attachments, :author).new("", [cat_picture], poster)
    client = FakeClient.new(answers: ["Hi!"])
    answer_ai_channel_message(event, client, history)
    assert_includes client.requests.first[:input].first[:content], "(replying to b (777): [image 42: cat.png])"
  end

  def test_reply_is_written_to_the_log
    answer_ai_channel_message(FakeAiEvent.new("hello"), FakeClient.new(answers: ["A reply to find in the log"]), [])
    logged = Dir.glob(File.join(MESSAGE_LOG_DIR, "**", "*.log")).map { |path| File.read(path) }.join
    assert_includes logged, "My Server #general | Cake (999): A reply to find in the log"
  end

  def test_compaction_runs_when_history_is_full
    history = []
    44.times { |i| add_user_message(history, "Bach", 123, "m#{i}", Time.now, message_id: i + 1) }
    client = FakeClient.new(answers: ["Hi!", { summary: "s", events: [], user_personalities: [] }.to_json])
    answer_ai_channel_message(FakeAiEvent.new("one more", message_id: 99), client, history)
    assert_equal 2, client.requests.length
    assert history.length <= COMPACT_TARGET_MESSAGES
  end

  def test_compaction_uses_the_bots_name_in_this_server
    history = []
    44.times { |i| add_user_message(history, "Bach", 123, "m#{i}", Time.now, message_id: i + 1) }
    client = FakeClient.new(answers: ["Hi!", { summary: "s", events: [], user_personalities: [] }.to_json])
    answer_ai_channel_message(FakeAiEvent.new("one more", message_id: 99, bot_name: "Mochi"), client, history)
    assert_includes client.requests.last[:instructions], "Discord bot called Mochi"
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
