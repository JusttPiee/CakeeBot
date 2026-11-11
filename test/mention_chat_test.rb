require_relative "test_helper"
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
    bot = Struct.new(:token).new("fake-token")
    event = Struct.new(:server, :author, :channel, :bot).new(Struct.new(:id).new(1), Struct.new(:id, :display_name).new(123, "Bach"), channel, bot)
    context = mention_context(event)
    assert_equal({ server_id: 1, channel_id: nil, requester_id: 123, requester_name: "Bach" }, context.except(:channel))
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
end
