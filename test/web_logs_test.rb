require_relative "web_test_helper"

class WebLogsTest < WebApiTest
  def setup
    super
    FileUtils.rm_rf(Dir.glob(File.join(MESSAGE_LOG_DIR, "*")))
  end

  # Add one line to the log file of that hour, like the bot does
  def write_log(time, line)
    append_message_log(line, message_log_path(time))
  end

  def test_reads_a_day_across_hour_files_and_continues_from_a_cursor
    write_log(Time.new(2026, 11, 11, 1, 46, 25), "[2026-11-11 01:46:25] Test Server #general | sylvie (5): !buildmemory")
    write_log(Time.new(2026, 11, 11, 2, 0, 1), "[2026-11-11 02:00:01] 🔌 Disconnected from Discord")
    api :get, "/api/logs?day=2026-11-11"
    assert_equal 2, json["cursor"]
    assert_equal [{ "time" => "01:46:25", "kind" => "chat", "place" => "Test Server #general", "text" => "sylvie: !buildmemory" },
                  { "time" => "02:00:01", "kind" => "system", "place" => "", "text" => "🔌 Disconnected from Discord" }], json["lines"]
    write_log(Time.new(2026, 11, 11, 2, 5, 0), "[2026-11-11 02:05:00] 🧠 new line")
    api :get, "/api/logs?day=2026-11-11&after=2"
    assert_equal ["🧠 new line"], json["lines"].map { |line| line["text"] }
    assert_equal 3, json["cursor"]
  end

  def test_first_read_gives_only_the_last_page
    lines = (0...(LOG_PAGE_LINES + 5)).map { |i| "[2026-11-10 03:00:00] line #{i}" }
    write_log(Time.new(2026, 11, 10, 3), lines.join("\n"))
    api :get, "/api/logs?day=2026-11-10"
    assert_equal LOG_PAGE_LINES, json["lines"].length
    assert_equal "line #{LOG_PAGE_LINES + 4}", json["lines"].last["text"]
    assert_equal LOG_PAGE_LINES + 5, json["cursor"]
  end

  def test_a_cursor_past_the_end_starts_over
    write_log(Time.new(2026, 11, 10, 3), "[2026-11-10 03:00:00] only line")
    api :get, "/api/logs?day=2026-11-10&after=50"
    assert_equal ["only line"], json["lines"].map { |line| line["text"] }
  end

  def test_tells_chat_lines_from_system_lines
    assert_equal({ time: "14:02:11", kind: "chat", place: "DM", text: "Piee: valorant? (not now): ok" },
                 parse_log_line("[2026-11-03 14:02:11] DM | Piee (123): valorant? (not now): ok"))
    assert_equal({ time: "14:02:11", kind: "system", place: "", text: "⚠️ Could not write | odd (text)" },
                 parse_log_line("[2026-11-03 14:02:11] ⚠️ Could not write | odd (text)"))
    assert_equal({ time: "", kind: "system", place: "", text: "a line written by hand" },
                 parse_log_line("a line written by hand"))
  end

  def test_lists_days_newest_first_and_handles_odd_input
    write_log(Time.new(2026, 11, 10, 3), "x")
    FileUtils.mkdir_p(File.join(MESSAGE_LOG_DIR, "2026-11-11"))
    File.binwrite(File.join(MESSAGE_LOG_DIR, "2026-11-11", "03.log"), "bad bytes \xFF here\n".b) # saved in another encoding
    FileUtils.mkdir_p(File.join(MESSAGE_LOG_DIR, "not-a-day"))
    api :get, "/api/logs/days"
    assert_equal ["2026-11-11", "2026-11-10"], json
    api :get, "/api/logs?day=2026-11-11"
    assert_equal 200, last_response.status # scrubbed, not a crash
    assert_equal ["bad bytes ? here"], json["lines"].map { |line| line["text"] }
    api :get, "/api/logs?day=..%2F..%2Fmemory"
    assert_equal 404, last_response.status
    api :get, "/api/logs"
    assert_equal 404, last_response.status
    api :get, "/api/logs?day=2020-01-01"
    assert_equal({ "cursor" => 0, "lines" => [] }, json)
  end
end
