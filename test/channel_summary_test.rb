require_relative "test_helper"
require_relative "../channel_summary"

# The rolling summary of one AI channel: memory/<server_id>/channels/<channel_id>.md
class ChannelSummaryTest < Minitest::Test
  def setup
    clear_test_memory
  end

  def test_missing_summary
    assert_equal({ text: "", last_message_id: nil }, read_channel_summary(1, 555))
  end

  def test_write_then_read
    write_channel_summary(1, 555, "We talked about pho.", 9001, Time.new(2026, 11, 4, 14, 2))
    assert_equal({ text: "We talked about pho.", last_message_id: 9001 }, read_channel_summary(1, 555))
    assert_includes read_memory_file(1, "channels/555.md"), "updated: 2026-11-04 14:02"
  end

  def test_summary_without_an_id
    write_channel_summary(1, 555, "Hi.", nil)
    assert_nil read_channel_summary(1, 555)[:last_message_id]
  end
end
