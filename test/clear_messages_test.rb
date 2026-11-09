require_relative "test_helper"
require_relative "fake_discord"
require_relative "../config"
require_relative "../clear_messages"
require_relative "../prompts" # PROMPTS_DIR

# A channel that remembers what the bot deleted, and reads its messages like a ReadingChannel
class ClearChannel < HistoryChannel
  attr_reader :deleted, :delete_calls, :temporary

  def initialize(messages, error: nil)
    super(messages)
    @delete_error = error
    @deleted = []
    @delete_calls = 0
    @temporary = []
  end

  # Like discordrb's channel.send_temporary_message: kept with how long it stays
  def send_temporary_message(text, seconds)
    @temporary << [text, seconds]
    nil
  end

  def delete_message(id)
    delete(id)
  end

  def delete_messages(ids)
    raise ArgumentError, "bulk delete needs 2 to 100" unless ids.length.between?(2, 100)

    delete(*ids)
  end

  private

  def delete(*ids)
    raise @delete_error if @delete_error

    @delete_calls += 1
    @deleted.concat(ids)
  end
end

# Tests read the fake channel as it is (no Discord)
module ClearReadAsIs
  def self.new(channel, _bot) = channel
end

# The !clear message: what the bot needs from event.message
CommandMessage = Struct.new(:id)

# A !clear command event. It has no send_temporary_message on purpose: discordrb 3.8's version is broken,
# so the code must use the channel's (temporary_note.rb).
class ClearEvent < CommandEvent
  attr_reader :channel, :message

  def initialize(channel, command_id, user: CommandUser.new(123, "Bach", true), server: HistoryServer.new(1, "Test Server", [], nil))
    super(server, user)
    @channel = channel
    @message = CommandMessage.new(command_id)
  end

  def bot = nil
  def temporary = @channel.temporary
end

class ClearMessagesTest < Minitest::Test
  BACH = HistoryAuthor.new(123, "Bach", false)
  PIE = HistoryAuthor.new(456, "Pie", false)

  def setup
    LOGS.clear
  end

  # Messages sent a few minutes ago, ids 1..n, from the given authors in turn
  def recent_messages(count, authors = [PIE])
    start = Time.now - 3600
    (1..count).map { |i| HistoryMessage.new(i, authors[(i - 1) % authors.length], "message #{i}", start + i) }
  end

  # The channel's messages plus the !clear command as the newest one
  def channel_with(messages)
    command = HistoryMessage.new(messages.length + 1, BACH, "!clear", Time.now)
    [ClearChannel.new(messages + [command]), command.id]
  end

  def clear(args, messages)
    channel, command_id = channel_with(messages)
    event = ClearEvent.new(channel, command_id)
    clear_command(event, args, ClearReadAsIs)
    [event, channel, command_id]
  end

  # --- reading the command ---

  def test_parses_an_amount
    assert_equal({ user_id: nil, amount: 50 }, parse_clear_arguments(["50"]))
  end

  def test_parses_a_person_and_an_amount
    assert_equal({ user_id: "456", amount: 50 }, parse_clear_arguments(["<@456>", "50"]))
    assert_equal({ user_id: "456", amount: 5 }, parse_clear_arguments(["<@!456>", "5"]))
    assert_equal({ user_id: "456", amount: 5 }, parse_clear_arguments(["456", "5"]))
  end

  def test_rejects_bad_commands
    assert_nil parse_clear_arguments([])
    assert_nil parse_clear_arguments(["abc"])
    assert_nil parse_clear_arguments(["0"])
    assert_nil parse_clear_arguments(["101"])
    assert_nil parse_clear_arguments(["@Pie", "5"]) # a typed name, not a real mention
    assert_nil parse_clear_arguments(["<@456>", "5", "extra"])
  end

  # --- clearing ---

  def test_deletes_the_newest_messages_and_the_command
    _event, channel, command_id = clear(["3"], recent_messages(10))
    assert_equal [10, 9, 8, command_id].sort, channel.deleted.sort
    assert_equal 1, channel.delete_calls # all in one bulk delete
  end

  def test_only_deletes_that_persons_messages
    _event, channel, command_id = clear(["<@456>", "2"], recent_messages(10, [PIE, BACH])) # Pie wrote the odd ids
    assert_equal [9, 7, command_id].sort, channel.deleted.sort
  end

  def test_looks_further_back_for_a_person
    messages = recent_messages(1, [PIE]) + recent_messages(300, [BACH]).map { |m| HistoryMessage.new(m.id + 1, m.author, m.content, m.creation_time) }
    _event, channel, command_id = clear(["<@456>", "5"], messages)
    assert_equal [1, command_id].sort, channel.deleted.sort # Pie's only message, 300 messages back
  end

  def test_skips_messages_older_than_14_days
    old = HistoryMessage.new(1, PIE, "old", Time.now - 15 * 24 * 3600)
    event, channel, command_id = clear(["5"], [old] + recent_messages(2).map { |m| HistoryMessage.new(m.id + 1, m.author, m.content, m.creation_time) })
    assert_equal [2, 3, command_id].sort, channel.deleted.sort
    assert_includes event.temporary.last.first, "Skipped 1 older than 14 days"
  end

  def test_the_report_disappears_after_a_few_seconds
    event, _channel, _command_id = clear(["2"], recent_messages(5))
    text, seconds = event.temporary.last
    assert_equal "🧹 Deleted 2 messages.", text
    assert_equal CLEAR_REPORT_SECONDS, seconds
  end

  def test_the_report_names_the_person
    event, _channel, _command_id = clear(["<@456>", "1"], recent_messages(3))
    assert_equal "🧹 Deleted 1 message from <@456>.", event.temporary.last.first
  end

  def test_nothing_to_delete_still_removes_the_command
    _event, channel, command_id = clear(["<@789>", "5"], recent_messages(3))
    assert_equal [command_id], channel.deleted
  end

  def test_is_logged
    clear(["2"], recent_messages(5))
    assert(LOGS.any? { |line| line.include?("!clear by Bach (123)") && line.include?("deleted 2 from everyone") })
  end

  # --- who may use it ---

  def test_only_admins
    channel, command_id = channel_with(recent_messages(5))
    event = ClearEvent.new(channel, command_id, user: CommandUser.new(456, "Pie", false))
    clear_command(event, ["5"], ClearReadAsIs)
    assert_includes event.responses.last, "Only admins"
    assert_empty channel.deleted
  end

  def test_only_in_a_server
    channel, command_id = channel_with(recent_messages(5))
    event = ClearEvent.new(channel, command_id, server: nil)
    clear_command(event, ["5"], ClearReadAsIs)
    assert_includes event.responses.last, "only works in a server"
  end

  def test_a_bad_command_shows_the_usage
    event, channel, _command_id = clear(["lots"], recent_messages(5))
    assert_equal CLEAR_USAGE, event.responses.last
    assert_empty channel.deleted
  end

  def test_a_discord_error_does_not_crash
    channel = ClearChannel.new(recent_messages(5), error: RuntimeError.new("boom"))
    event = ClearEvent.new(channel, 99)
    clear_command(event, ["2"], ClearReadAsIs)
    assert_includes event.responses.last, "Could not delete"
  end

  def test_the_ai_knows_about_the_command
    assert_includes File.read(File.join(PROMPTS_DIR, "capabilities.txt")), "!clear"
  end
end
