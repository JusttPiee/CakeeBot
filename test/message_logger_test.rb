require_relative "test_helper"
require "tmpdir"
require_relative "../message_logger"

# Messages are logged to one file per hour, in one folder per day: logs/2026-11-07/14.log
class MessageLoggerTest < Minitest::Test
  FakeAuthor = Struct.new(:display_name, :id)
  FakeMessage = Struct.new(:content)
  FakeEvent = Struct.new(:server, :author, :message)

  def setup
    LOGS.clear
  end

  def dm_from_bach(text)
    FakeEvent.new(nil, FakeAuthor.new("Bach", 123), FakeMessage.new(text))
  end

  def test_path_has_a_folder_per_day_and_a_file_per_hour
    path = message_log_path(Time.new(2026, 11, 7, 14, 59, 59), "logs")
    assert_equal File.join("logs", "2026-11-07", "14.log"), path
  end

  def test_early_hours_keep_their_leading_zero
    path = message_log_path(Time.new(2026, 11, 7, 9, 0, 0), "logs")
    assert_equal File.join("logs", "2026-11-07", "09.log"), path
  end

  def test_append_creates_the_missing_folders
    Dir.mktmpdir do |dir|
      path = File.join(dir, "logs", "2026-11-07", "14.log")
      append_message_log("first", path)
      assert_equal "first\n", File.read(path)
    end
  end

  def test_append_adds_to_the_end_of_the_file
    Dir.mktmpdir do |dir|
      path = File.join(dir, "14.log")
      append_message_log("first", path)
      append_message_log("second", path)
      assert_equal "first\nsecond\n", File.read(path)
    end
  end

  def test_received_message_goes_to_the_file_for_the_current_hour
    Dir.mktmpdir do |dir|
      now = Time.new(2026, 11, 7, 14, 2, 11)
      capture_io { log_received_message(dm_from_bach("hello"), now, dir) }
      line = File.read(File.join(dir, "2026-11-07", "14.log"))
      assert_equal "[2026-11-07 14:02:11] DM | Bach (123): hello\n", line
    end
  end

  # --- Bot replies ---

  def channel_event
    server = Struct.new(:name, :bot).new("My Server", Struct.new(:display_name).new("Mochi"))
    channel = Struct.new(:name).new("general")
    bot = Struct.new(:profile).new(Struct.new(:id).new(999))
    Struct.new(:server, :channel, :bot).new(server, channel, bot)
  end

  def test_bot_reply_is_saved_with_the_bots_name
    Dir.mktmpdir do |dir|
      log_bot_reply(channel_event, "hi :3", Time.new(2026, 11, 7, 14, 2, 11), dir)
      line = File.read(File.join(dir, "2026-11-07", "14.log"))
      assert_equal "[2026-11-07 14:02:11] My Server #general | Mochi (999): hi :3\n", line
    end
  end

  def test_long_bot_reply_stays_on_one_line
    Dir.mktmpdir do |dir|
      log_bot_reply(channel_event, "one\ntwo", Time.new(2026, 11, 7, 14, 2, 11), dir)
      assert_equal 1, File.readlines(File.join(dir, "2026-11-07", "14.log")).length
    end
  end

  def test_bot_reply_is_not_printed_in_the_terminal
    Dir.mktmpdir do |dir|
      out, = capture_io { log_bot_reply(channel_event, "hi", Time.new(2026, 11, 7, 14, 2, 11), dir) }
      assert_empty out
    end
  end

  # --- Status lines ---

  def test_status_line_goes_to_the_terminal_and_the_file
    Dir.mktmpdir do |dir|
      out, = capture_io { log_status_line("Compacted", Time.new(2026, 11, 7, 14, 2, 11), dir) }
      assert_equal "[2026-11-07 14:02:11] Compacted\n", out
      assert_equal "[2026-11-07 14:02:11] Compacted\n", File.read(File.join(dir, "2026-11-07", "14.log"))
    end
  end

  def test_status_line_stays_on_one_line_in_the_file
    Dir.mktmpdir do |dir|
      capture_io { log_status_line("one\ntwo", Time.new(2026, 11, 7, 14, 2, 11), dir) }
      assert_equal 1, File.readlines(File.join(dir, "2026-11-07", "14.log")).length
    end
  end

  # A file where the log folder should be: the folders can't be created, so writing fails
  def test_status_line_still_prints_when_the_file_cannot_be_written
    Dir.mktmpdir do |dir|
      blocked = File.join(dir, "not_a_folder")
      File.write(blocked, "")
      out, = capture_io { log_status_line("Compacted", Time.new(2026, 11, 7, 14, 2, 11), blocked) }
      assert_includes out, "Compacted"
      assert_includes out, "Could not write"
    end
  end

  def test_messages_in_different_hours_go_to_different_files
    Dir.mktmpdir do |dir|
      capture_io do
        log_received_message(dm_from_bach("before"), Time.new(2026, 11, 7, 14, 59, 0), dir)
        log_received_message(dm_from_bach("after"), Time.new(2026, 11, 7, 15, 0, 0), dir)
      end
      assert_includes File.read(File.join(dir, "2026-11-07", "14.log")), "before"
      assert_includes File.read(File.join(dir, "2026-11-07", "15.log")), "after"
    end
  end
end
