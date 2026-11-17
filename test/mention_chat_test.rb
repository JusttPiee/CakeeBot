require_relative "test_helper"
require "faraday"
require_relative "../config"
require_relative "../mention_chat"

# Pretend Discord message: who it mentions, and which message it replies to (if any)
MentionUser = Struct.new(:id)
class MentionMessage
  attr_reader :mentions, :referenced_message

  def initialize(mentions: [], replying_to: nil)
    @mentions = mentions.map { |id| MentionUser.new(id) }
    @referenced_message = replying_to && Struct.new(:author).new(MentionUser.new(replying_to))
  end

  def reply? = !@referenced_message.nil?
end

class MentionChatTest < Minitest::Test
  BOT_ID = 999

  def test_at_mention_counts
    assert mentions_bot?(MentionMessage.new(mentions: [BOT_ID]), BOT_ID)
  end

  def test_replying_to_the_bot_counts
    assert mentions_bot?(MentionMessage.new(replying_to: BOT_ID), BOT_ID)
  end

  def test_normal_message_does_not_count
    refute mentions_bot?(MentionMessage.new, BOT_ID)
  end

  def test_mentioning_someone_else_does_not_count
    refute mentions_bot?(MentionMessage.new(mentions: [123]), BOT_ID)
  end

  def test_replying_to_someone_else_does_not_count
    refute mentions_bot?(MentionMessage.new(replying_to: 123), BOT_ID)
  end

  def test_bot_mention_is_shown_as_its_name
    history = [{ role: "user", content: "Piee (123): <@999> weather?" },
               { role: "user", content: "Piee (123): <@!999> and <@456> too" }]
    name_bot_mentions(history, BOT_ID, "Cake")
    assert_equal "Piee (123): @Cake weather?", history[0][:content]
    assert_equal "Piee (123): @Cake and <@456> too", history[1][:content] # other people's mentions stay
  end

  # No channel_id (so no summary), but the channel itself is there for search_channel_history
  def test_mention_context_has_no_channel_id_so_no_summary
    channel = Struct.new(:id, :name).new(555, "general")
    bot = Struct.new(:token, :profile).new("fake-token", Struct.new(:avatar_url).new(nil))
    event = Struct.new(:server, :author, :channel, :bot, :message).new(Struct.new(:id).new(1), Struct.new(:id, :display_name).new(123, "Bach"), channel, bot, Struct.new(:id).new(500))
    context = mention_context(event)
    assert_equal({ server_id: 1, channel_id: nil, requester_id: 123, requester_name: "Bach" },
                 context.slice(:server_id, :channel_id, :requester_id, :requester_name))
    assert_equal 500, context[:request_message_id] # plus the command tools' facts (command_context.rb)
    assert_instance_of ReadingChannel, context[:channel] # reads raw messages, see discord_history.rb
    assert_equal 555, context[:channel].id
  end

  # --- tags Cake doesn't answer (another bot), for the shared recent memory ---

  TagAuthor = Struct.new(:id, :display_name, :bot) do
    def bot_account? = bot
  end
  TagMessage = Struct.new(:content, :mentions) do
    def attachments = []
    def reply? = false
  end
  TagEvent = Struct.new(:server, :author, :channel, :bot, :message)

  def tag_event(text, bot_author: true, mentions: [], channel_id: 555)
    citlali = TagAuthor.new(1333, "Citlali", bot_author)
    bot = Struct.new(:profile).new(MentionUser.new(BOT_ID))
    TagEvent.new(Struct.new(:id).new(1), citlali, Struct.new(:id, :name).new(channel_id, "test"), bot,
                 TagMessage.new(text, mentions.map { |id| MentionUser.new(id) }))
  end

  def with_tag_setup
    RECENT_ACTIVITY.clear
    @config = File.join(Dir.mktmpdir("cake-tags"), "ai_config.txt")
    yield
  ensure
    RECENT_ACTIVITY.clear
  end

  def test_another_bots_tag_is_recorded_as_tagged
    with_tag_setup do
      note_unanswered_tag(tag_event("hey <@999>, what's up?"), @config) # Discord left `mentions` empty
      entry = all_recent_entries(1).first
      assert_equal [:tagged, "Citlali [bot]"], entry.values_at(:kind, :speaker_name)
      assert_includes entry[:text], "what's up?"
    end
  end

  def test_a_persons_tag_is_not_recorded_as_tagged # Review Focus 5: Cake answers people, that is an exchange
    with_tag_setup do
      note_unanswered_tag(tag_event("hey <@999>", bot_author: false), @config)
      assert_empty all_recent_entries(1)
    end
  end

  def test_a_bot_tag_cake_will_answer_is_not_recorded_twice
    with_tag_setup do
      note_unanswered_tag(tag_event("hey <@999>", mentions: [BOT_ID]), @config) # the mention handler answers this one
      assert_empty all_recent_entries(1)
    end
  end

  def test_a_tag_in_an_ai_channel_is_not_recorded_as_tagged # Review Focus 5
    with_tag_setup do
      add_ai_channel(@config, 555)
      note_unanswered_tag(tag_event("hey <@999>"), @config)
      assert_empty all_recent_entries(1)
    end
  end

  def test_a_message_without_a_tag_is_not_recorded
    with_tag_setup do
      note_unanswered_tag(tag_event("talking about cake"), @config)
      assert_empty all_recent_entries(1)
    end
  end

  # --- a command turn when @mentioned (the AI runs show_help) ---

  # Only what answer_mention uses. history is what the fake reader gives back.
  class AnswerEvent
    Author = Struct.new(:id, :display_name)
    Channel = Struct.new(:id, :name) do
      def start_typing = nil
      def send_message(*args) = (posted << args) && nil
      def posted = (@posted ||= [])
      def history(_amount) = []
    end
    Bot = Struct.new(:profile, :token)
    Profile = Struct.new(:id, :avatar_url)

    attr_reader :sent, :author, :server, :channel

    def initialize(text)
      @text = text
      @sent = []
      @author = Author.new(123, "Bach")
      @server = Struct.new(:id, :bot, :name).new(1, Struct.new(:display_name).new("Cake"), "My Server")
      @channel = Channel.new(555, "general")
    end

    def bot = Bot.new(Profile.new(BOT_ID, nil), "fake-token")
    def message = self
    def id = 500
    def content = @text
    def attachments = []
    def reply? = false

    # edits: every text a sent message was edited into, in order
    def edits = (@edits ||= [])

    def reply!(text, mention_user:)
      @sent << text
      SentMessage.new(@sent.length, self)
    end

    # Editing a sent message changes what `sent` shows, so `sent` is what the channel shows in the end
    def edited(id, text)
      edits << text
      @sent[id - 1] = text
    end

    # A message Cake sent. edit_without_ping works like the one in message_edit.rb.
    SentMessage = Struct.new(:id, :event) do
      def edit_without_ping(text) = event.edited(id, text) && self
    end
  end

  def test_reply_goes_into_the_thinking_message
    event = AnswerEvent.new("<@999> hi")
    answer_mention(event, FakeClient.new(answers: ["Hi!"]), nil, ReadAsIs)
    assert_equal ["Hi!"], event.edits
    assert_equal ["Hi!"], event.sent # the Thinking line became the answer
  end

  def test_a_crash_turns_thinking_into_unavailable
    event = AnswerEvent.new("<@999> hi")
    assert_raises(RuntimeError) do
      answer_mention(event, FakeClient.new(error: RuntimeError.new("odd response")), nil, ReadAsIs)
    end
    assert_equal [AI_UNAVAILABLE_MESSAGE], event.edits
  end

  def test_unavailable_answer_is_edited_into_thinking
    event = AnswerEvent.new("<@999> hi")
    answer_mention(event, FakeClient.new(error: Faraday::ConnectionFailed.new("x")), nil, ReadAsIs)
    assert_equal 1, event.edits.length
    assert_includes event.sent.first, "unavailable"
  end

  # Reads the fake channel as it is (no Discord)
  module ReadAsIs
    def self.new(channel, _bot) = channel
  end

  def test_mention_command_turn_skips_recent_activity
    RECENT_ACTIVITY.clear
    call = { "type" => "function_call", "call_id" => "c1", "name" => "show_help", "arguments" => '{"category":"music"}' }
    event = AnswerEvent.new("<@999> music commands?")
    answer_mention(event, FakeClient.new(answers: [{ tool_calls: [call] }, "Here you go!"]), nil, ReadAsIs)
    assert_equal ["Here you go!"], event.sent
    assert_equal 1, event.channel.posted.length
    assert_empty all_recent_entries(1)
  ensure
    RECENT_ACTIVITY.clear
  end

  def test_a_normal_mention_is_recorded
    RECENT_ACTIVITY.clear
    event = AnswerEvent.new("<@999> hi")
    answer_mention(event, FakeClient.new(answers: ["Hi!"]), nil, ReadAsIs)
    assert_equal 1, all_recent_entries(1).length
  ensure
    RECENT_ACTIVITY.clear
  end

  def test_mention_empty_answer_after_a_command_says_done
    RECENT_ACTIVITY.clear
    call = { "type" => "function_call", "call_id" => "c1", "name" => "show_help", "arguments" => '{"category":"music"}' }
    client = FakeClient.new(answers: [{ tool_calls: [call] }, "", { tool_calls: [call] }, ""])
    event = AnswerEvent.new("<@999> music commands?")
    answer_mention(event, client, nil, ReadAsIs)
    assert_equal [COMMAND_DONE_REPLY], event.sent
    assert_equal 1, event.channel.posted.length
    assert_equal 2, client.requests.length
    assert_empty all_recent_entries(1)
  ensure
    RECENT_ACTIVITY.clear
  end
end
