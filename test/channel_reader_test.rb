require_relative "test_helper"
require_relative "../channel_reader"

# Pretend Discord messages and authors (only the fields the reader uses)
FakeAuthor  = Struct.new(:id, :display_name)
FakeMessage = Struct.new(:author, :content)

# Pretend channel: history(n) returns the newest n messages, newest first, like Discord
class FakeChannel
  attr_reader :name

  def initialize(messages, error: nil)
    @messages = messages # oldest first, easier to read in tests
    @error = error
    @name = "general"
  end

  def history(amount)
    raise @error if @error
    @messages.last(amount).reverse
  end
end

class ChannelReaderTest < Minitest::Test
  BOT_ID = 999
  PIEE = FakeAuthor.new(123, "Piee")
  BOT  = FakeAuthor.new(BOT_ID, "Cake")

  def say(author, text) = FakeMessage.new(author, text)

  def test_messages_are_in_oldest_first_order
    channel = FakeChannel.new([say(PIEE, "first"), say(PIEE, "second")])
    history = load_channel_history(channel, BOT_ID)
    assert_equal ["Piee (123): first", "Piee (123): second"], history.map { |m| m[:content] }
  end

  def test_bot_messages_become_assistant_messages
    channel = FakeChannel.new([say(PIEE, "hi"), say(BOT, "hello Piee")])
    history = load_channel_history(channel, BOT_ID)
    assert_equal({ role: "assistant", content: "hello Piee" }, history.last)
  end

  def test_other_people_get_the_name_and_id_prefix
    channel = FakeChannel.new([say(PIEE, "valorant?")])
    assert_equal({ role: "user", content: "Piee (123): valorant?" }, load_channel_history(channel, BOT_ID).first)
  end

  def test_commands_are_included
    channel = FakeChannel.new([say(PIEE, "!play")])
    assert_equal "Piee (123): !play", load_channel_history(channel, BOT_ID).first[:content]
  end

  def test_messages_without_text_are_skipped
    channel = FakeChannel.new([say(PIEE, ""), say(BOT, "   "), say(PIEE, "real text")])
    assert_equal 1, load_channel_history(channel, BOT_ID).length
  end

  def test_loads_at_most_the_history_limit
    messages = 100.times.map { |i| say(i.even? ? PIEE : BOT, "message #{i}") }
    history = load_channel_history(FakeChannel.new(messages), BOT_ID)
    assert history.length <= MAX_HISTORY_MESSAGES
    assert_equal "message 99", history.last[:content] # the newest message is kept
  end

  def test_token_limit_still_applies
    messages = 10.times.map { say(PIEE, "a" * 4_000) } # about 1,000 tokens each
    history = load_channel_history(FakeChannel.new(messages), BOT_ID)
    assert estimate_tokens(history) <= MAX_HISTORY_TOKENS
  end

  def test_discord_error_gives_empty_memory
    channel = FakeChannel.new([], error: RuntimeError.new("Missing Access"))
    assert_equal [], load_channel_history(channel, BOT_ID)
  end
end
