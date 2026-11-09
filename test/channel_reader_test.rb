require_relative "test_helper"
require_relative "../channel_reader"

# Pretend Discord messages and authors (only the fields the reader uses)
FakeAuthor  = Struct.new(:id, :display_name)
FakeMessage = Struct.new(:author, :content, :creation_time, :id, :attachments, :referenced_message) do
  def attachments = self[:attachments] || []
  def reply? = !referenced_message.nil?
end
FakeImage = Struct.new(:id, :filename, :proxy_url, :url, :width, :height, :content_type) do
  def image? = true
end

# Pretend channel: history(n) returns the newest n messages, newest first, like Discord
FakeServer = Struct.new(:name, :id)

class FakeChannel
  attr_reader :name, :id, :server

  def initialize(messages, error: nil, id: 555)
    @messages = messages # oldest first, easier to read in tests
    @error = error
    @name = "general"
    @id = id
    @server = FakeServer.new("Test Server", 1)
  end

  def history(amount)
    raise @error if @error
    @messages.last(amount).reverse
  end

  def cached_nickname(_user_id) = nil # like ReadingChannel: no nickname known
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

# Startup reads channels through a ReadingChannel (discord_history.rb), which calls Discord.
# Tests read the fake channel as it is instead.
module ReadAsIs
  def self.new(channel, _bot) = channel
end

class ChannelReaderTest < Minitest::Test
  def setup
    LOGS.clear
    clear_test_memory
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
    assert_equal({ role: "assistant", content: "hello Piee" }, history.last.slice(:role, :content))
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

  def cat_picture
    FakeImage.new(42, "cat.png", "https://media.discordapp.net/cat.png", "https://cdn.discordapp.com/cat.png", 800, 600, "image/png")
  end

  def test_image_only_message_is_kept_with_a_marker
    channel = FakeChannel.new([FakeMessage.new(PIEE, "", Time.now, 1, [cat_picture])])
    first = load_channel_history(channel, BOT_ID).first
    assert_equal "Piee (123): [image 42: cat.png]", first[:content]
    assert_equal "42", first[:images].first[:id]
  end

  # The bug: mention chats read the history again every time, and older replies lost who they answered
  def test_every_reply_in_the_history_keeps_who_it_answers
    b = FakeAuthor.new(777, "b")
    original = FakeMessage.new(b, "", Time.now, 1, [cat_picture])
    reply = FakeMessage.new(PIEE, "what is this", Time.now, 2, [], original)
    follow_up = FakeMessage.new(PIEE, "who sent the pic?", Time.now, 3)
    history = load_channel_history(FakeChannel.new([reply, follow_up]), BOT_ID)
    assert_equal "Piee (123): what is this (replying to b (777): [image 42: cat.png])", history.first[:content]
    assert_equal "42", history.first[:images].first[:id]
  end

  def test_the_bots_own_images_are_not_marked
    channel = FakeChannel.new([FakeMessage.new(BOT, "here", Time.now, 1, [cat_picture])])
    assert_equal "here", load_channel_history(channel, BOT_ID).first[:content]
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

  def test_messages_up_to_after_id_are_skipped
    channel = FakeChannel.new([FakeMessage.new(PIEE, "old", Time.now, 10), FakeMessage.new(PIEE, "new", Time.now, 11)])
    history = load_channel_history(channel, BOT_ID, after_id: 10)
    assert_equal ["Piee (123): new"], history.map { |m| m[:content] }
    assert_equal 11, history.first[:message_id]
  end

  # --- Authors from Discord's JSON (people who left the server) ---

  # discordrb would look this author up in the member list, which asks Discord when they left the server
  class LookupAuthorMessage < FakeMessage
    def author = raise("member lookup")
  end

  def raw_for(author_id, name, replied: nil)
    raw = { "author" => { "id" => author_id.to_s, "username" => name.downcase, "global_name" => name } }
    raw["referenced_message"] = replied if replied
    raw
  end

  def test_authors_come_from_the_json_without_a_lookup
    message = LookupAuthorMessage.new(nil, "hi", Time.now, 1)
    wrapped = message_with_json_author(message, raw_for(456, "Pie"), FakeChannel.new([]))
    history = build_history_from_messages([wrapped], BOT_ID)
    assert_equal "Pie (456): hi", history.first[:content]
  end

  def test_the_replied_author_comes_from_the_json_too
    replied = LookupAuthorMessage.new(nil, "gg ez", Time.now, 1)
    reply = LookupAuthorMessage.new(nil, "no u", Time.now, 2, [], replied)
    raw = raw_for(123, "Piee", replied: raw_for(456, "Pie"))
    history = build_history_from_messages([message_with_json_author(reply, raw, FakeChannel.new([]))], BOT_ID)
    assert_equal "Piee (123): no u (replying to Pie (456): gg ez)", history.first[:content]
  end

  def test_the_server_nickname_is_used_when_known
    channel = FakeChannel.new([])
    def channel.cached_nickname(_user_id) = "Boss"
    wrapped = message_with_json_author(LookupAuthorMessage.new(nil, "hi", Time.now, 1), raw_for(123, "Bach"), channel)
    assert_equal "Boss", wrapped.author.display_name
  end

  def test_a_message_that_is_not_a_reply
    wrapped = message_with_json_author(LookupAuthorMessage.new(nil, "hi", Time.now, 1), raw_for(123, "Bach"), FakeChannel.new([]))
    refute wrapped.reply?
    assert_equal "hi", wrapped.content # everything else comes from the normal message
  end

  # --- Remembering after a restart ---

  def test_startup_loads_the_saved_ai_channel
    channel = FakeChannel.new([say(PIEE, "hi"), say(BOT, "hello Piee")])
    histories = create_history_store
    restore_ai_memory(FakeBot.new({ 555 => channel }), histories, ["555"], ReadAsIs) # ai_config.txt stores IDs as text
    assert_equal 2, histories[555].length
    assert_includes LOGS.last, "Test Server #general: loaded 2 messages"
  end

  def test_startup_loads_every_ai_channel_into_its_own_memory
    general = FakeChannel.new([say(PIEE, "in general")], id: 555)
    gaming = FakeChannel.new([say(PIEE, "in gaming"), say(BOT, "gg")], id: 777)
    histories = create_history_store
    restore_ai_memory(FakeBot.new({ 555 => general, 777 => gaming }), histories, %w[555 777], ReadAsIs)
    assert_equal ["Piee (123): in general"], histories[555].map { |m| m[:content] }
    assert_equal ["Piee (123): in gaming", "gg"], histories[777].map { |m| m[:content] }
  end

  def test_startup_with_ai_mode_off_loads_nothing
    histories = create_history_store
    restore_ai_memory(FakeBot.new, histories, [], ReadAsIs)
    assert_empty histories.keys
    assert_includes LOGS.last, "AI mode is off"
  end

  def test_startup_with_a_deleted_channel_does_not_crash
    histories = create_history_store
    restore_ai_memory(FakeBot.new, histories, ["123"], ReadAsIs)
    assert_empty histories.keys
    assert_includes LOGS.last, "not found"
  end

  def test_startup_when_discord_refuses_does_not_crash
    restore_ai_memory(FakeBot.new(error: RuntimeError.new("Missing Access")), create_history_store, ["555"], ReadAsIs)
    assert_includes LOGS.last, "Could not open AI channel"
  end

  # --- Channel summary + restart ---

  def test_restart_skips_messages_already_in_the_summary
    write_channel_summary(1, 555, "earlier stuff", 10)
    channel = FakeChannel.new([FakeMessage.new(PIEE, "old", Time.now, 10), FakeMessage.new(PIEE, "new", Time.now, 11)])
    histories = create_history_store
    restore_ai_memory(FakeBot.new({ 555 => channel }), histories, ["555"], ReadAsIs)
    assert_equal ["Piee (123): new"], histories[555].map { |m| m[:content] }
  end

  def test_restart_without_summary_loads_everything
    channel = FakeChannel.new([FakeMessage.new(PIEE, "a", Time.now, 1), FakeMessage.new(PIEE, "b", Time.now, 2)])
    assert_equal 2, load_ai_channel_history(channel, BOT_ID).length
  end

  def test_ai_channel_keeps_more_than_the_high_mark_until_compaction
    messages = 10.times.map { |i| FakeMessage.new(PIEE, "a" * 2_400, Time.now, i + 1) } # about 600 tokens each
    history = load_ai_channel_history(FakeChannel.new(messages), BOT_ID)
    assert estimate_tokens(history) > MAX_HISTORY_TOKENS
    assert estimate_tokens(history) <= HARD_MAX_HISTORY_TOKENS
  end
end
