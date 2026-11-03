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

  def test_mention_context_has_no_channel_so_no_summary
    event = Struct.new(:server, :author).new(Struct.new(:id).new(1), Struct.new(:id, :display_name).new(123, "Bach"))
    assert_equal({ server_id: 1, channel_id: nil, requester_id: 123, requester_name: "Bach" }, mention_context(event))
  end
end
