# Pretend Discord objects for reading far back in channels (discord_history.rb).
# Used by channel_search_test.rb and build_memory_test.rb. Not a test file itself (no _test in the name).
require_relative "../discord_history"

# Messages are written as small structs in tests, and turned into Discord's raw JSON (hashes) when read.
# nickname: the server nickname discordrb would know for this person (nil = not known)
HistoryAuthor = Struct.new(:id, :display_name, :bot, :nickname)
HistoryMessage = Struct.new(:id, :author, :content, :creation_time) do
  # What Discord's API sends for this message
  def to_raw
    { "id" => id.to_s, "content" => content, "timestamp" => creation_time.iso8601(3),
      "author" => { "id" => author.id.to_s, "username" => author.display_name.downcase,
                    "global_name" => author.display_name, "bot" => author.bot ? true : false } }
  end
end

# Works like a ReadingChannel (discord_history.rb). raw_history works like Discord, newest first:
#   raw_history(amount, before_id): the newest `amount` messages older than before_id
#   raw_history(amount, nil, after_id): the oldest `amount` messages newer than after_id
# It remembers its requests, so tests can check that pages of 100 are used.
class HistoryChannel
  attr_reader :id, :name, :requests

  def initialize(messages, id: 555, name: "general", error: nil)
    @messages = messages # oldest first, easier to read in tests
    @id = id
    @name = name
    @error = error
    @requests = []
  end

  def raw_history(amount, before_id = nil, after_id = nil)
    @requests << (after_id ? [amount, before_id, after_id] : [amount, before_id])
    raise @error if @error

    page_of(amount, before_id, after_id).reverse.map(&:to_raw)
  end

  def cached_nickname(user_id)
    @messages.map(&:author).find { |author| author.id.to_s == user_id.to_s }&.nickname
  end

  private

  def page_of(amount, before_id, after_id)
    return @messages.select { |message| message.id > after_id }.first(amount) if after_id

    older = before_id ? @messages.select { |message| message.id < before_id } : @messages
    older.last(amount)
  end
end

# Test messages as plain hashes, like plain_messages makes from Discord's JSON
def plain_test_messages(messages)
  plain_messages(HistoryChannel.new(messages), messages.map(&:to_raw))
end

# A message whose id contains its time, like a real Discord id (see discord_id_for_time)
def dated_message(author, text, time)
  HistoryMessage.new(discord_id_for_time(time), author, text, time)
end

# bot: the bot as a member of the server (event.server.bot.display_name)
HistoryServer = Struct.new(:id, :name, :text_channels, :bot)

# Who typed a command. admin: true gives the administrator permission.
CommandUser = Struct.new(:id, :display_name, :admin) do
  def permission?(_permission) = admin ? true : false
end

# A command event (!forgetme, !buildmemory). Remembers everything the bot answered.
class CommandEvent
  attr_reader :server, :author, :responses

  def initialize(server, author)
    @server = server
    @author = author
    @responses = []
  end

  def user = @author

  def respond(text)
    @responses << text
    nil
  end
end

# n messages with ids 1..n, one minute apart, all from `author`
def history_messages(count, author, text: "message")
  start = Time.new(2026, 11, 1, 12, 0)
  (1..count).map { |i| HistoryMessage.new(i, author, "#{text} #{i}", start + i * 60) }
end
