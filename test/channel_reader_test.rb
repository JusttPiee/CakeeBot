require_relative "test_helper"
require_relative "../channel_reader"

# Pretend Discord messages and authors (only the fields the reader uses)
FakeAuthor  = Struct.new(:id, :display_name)
FakeMessage = Struct.new(:author, :content, :creation_time)

# Pretend channel: history(n) returns the newest n messages, newest first, like Discord
FakeServer = Struct.new(:name)

class FakeChannel
  attr_reader :name, :id, :server

  def initialize(messages, error: nil, id: 555)
    @messages = messages # oldest first, easier to read in tests
    @error = error
    @name = "general"
    @id = id
    @server = FakeServer.new("Test Server")
  end

  def history(amount)
    raise @error if @error
    @messages.last(amount).reverse
  end
end

# Pretend bot: knows some channels by ID, like bot.channel(id) in discordrb
class FakeBot
  def initialize(channels = {}, error: nil)
    @channels = channels
    @error = error
  end

  def channel(id)
    raise @error if @error
    @channels[id.to_i]
  end

  def profile = FakeAuthor.new(999, "Cake")
end

class ChannelReaderTest < Minitest::Test
  def setup
    LOGS.clear
  end

  BOT_ID = 999
  PIEE = FakeAuthor.new(123, "Piee")
  BOT  = FakeAuthor.new(BOT_ID, "Cake")

  def say(author, text, sent_at = Time.now) = FakeMessage.new(author, text, sent_at)

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
    first = load_channel_history(channel, BOT_ID).first
    assert_equal "user", first[:role]
    assert_equal "Piee (123): valorant?", first[:content]
  end

  def test_discord_send_time_is_kept_for_the_time_marker
    sent_at = Time.new(2026, 11, 1, 20, 0, 0)
    channel = FakeChannel.new([say(PIEE, "gn everyone", sent_at)])
    assert_equal sent_at, load_channel_history(channel, BOT_ID).first[:time]
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

  # --- Remembering after a restart ---

  def test_startup_loads_the_saved_ai_channel
    channel = FakeChannel.new([say(PIEE, "hi"), say(BOT, "hello Piee")])
    histories = create_history_store
    restore_ai_memory(FakeBot.new({ 555 => channel }), histories, ["555"]) # ai_config.txt stores IDs as text
    assert_equal 2, histories[555].length
    assert_includes LOGS.last, "Test Server #general: loaded 2 messages"
  end

  def test_startup_loads_every_ai_channel_into_its_own_memory
    general = FakeChannel.new([say(PIEE, "in general")], id: 555)
    gaming = FakeChannel.new([say(PIEE, "in gaming"), say(BOT, "gg")], id: 777)
    histories = create_history_store
    restore_ai_memory(FakeBot.new({ 555 => general, 777 => gaming }), histories, %w[555 777])
    assert_equal ["Piee (123): in general"], histories[555].map { |m| m[:content] }
    assert_equal ["Piee (123): in gaming", "gg"], histories[777].map { |m| m[:content] }
  end

  def test_startup_with_ai_mode_off_loads_nothing
    histories = create_history_store
    restore_ai_memory(FakeBot.new, histories, [])
    assert_empty histories.keys
    assert_includes LOGS.last, "AI mode is off"
  end

  def test_startup_with_a_deleted_channel_does_not_crash
    histories = create_history_store
    restore_ai_memory(FakeBot.new, histories, ["123"])
    assert_empty histories.keys
    assert_includes LOGS.last, "not found"
  end

  def test_startup_when_discord_refuses_does_not_crash
    restore_ai_memory(FakeBot.new(error: RuntimeError.new("Missing Access")), create_history_store, ["555"])
    assert_includes LOGS.last, "Could not open AI channel"
  end
end
