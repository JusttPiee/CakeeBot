require_relative "test_helper"
require_relative "../config"
require_relative "../help_cleanup"

# A channel that returns raw Discord messages, newest first
class CleanupChannel
  attr_reader :id

  def initialize(id, raws, error: nil)
    @id = id
    @raws = raws
    @error = error
  end

  def raw_history(_amount)
    raise @error if @error

    @raws
  end
end

class HelpCleanupTest < Minitest::Test
  BOT_ID = 1
  NOW = Time.utc(2026, 11, 18, 12, 0, 0)

  def raw(id, minutes_ago, author_id: BOT_ID, title: "#{HELP_TITLE} — Music")
    { "id" => id.to_s, "timestamp" => (NOW - minutes_ago * 60).iso8601,
      "author" => { "id" => author_id.to_s }, "embeds" => [{ "title" => title }] }
  end

  def setup
    @deleted = []
    @deleter = ->(channel_id, message_id) { @deleted << [channel_id, message_id] }
    @waits = []
    @later = []
    @scheduler = ->(seconds, &block) { @waits << seconds; @later << block }
  end

  def clean(channel)
    clean_help_in_channel(channel, BOT_ID, NOW, @scheduler, @deleter)
  end

  def test_old_help_is_deleted_now
    assert_equal 1, clean(CleanupChannel.new(9, [raw(50, 60)]))
    assert_equal [[9, "50"]], @deleted
  end

  def test_young_help_gets_the_rest_of_its_time
    assert_equal 0, clean(CleanupChannel.new(9, [raw(50, 2)]))
    assert_empty @deleted
    assert_equal [(HELP_CLOSE_AFTER_MINUTES - 2) * 60], @waits

    @later.each(&:call)
    assert_equal [[9, "50"]], @deleted
  end

  def test_other_messages_are_left_alone
    others = [raw(1, 60, author_id: 2), raw(2, 60, title: "🎵 Now playing"), raw(3, 60).merge("embeds" => [])]
    assert_equal 0, clean(CleanupChannel.new(9, others))
    assert_empty @deleted
  end

  def test_unreadable_channel_is_skipped
    assert_equal 0, clean(CleanupChannel.new(9, [], error: RuntimeError.new("no permission")))
  end

  def test_failed_delete_is_logged
    deleter = ->(_channel_id, _message_id) { raise "Unknown Message" }
    assert_equal 0, clean_help_in_channel(CleanupChannel.new(9, [raw(50, 60)]), BOT_ID, NOW, @scheduler, deleter)
    assert(LOGS.any? { |line| line.include?("could not delete a help message") })
  end
end
