require_relative "test_helper"
require_relative "../config"
require_relative "../recent_activity"

# The shared short-term memory of a server: what happened around Cake lately, in any channel.
class RecentActivityTest < Minitest::Test
  NOW = Time.new(2026, 11, 11, 12, 21, 0)
  PUBLIC_A = { id: "100", name: "test", public: true }.freeze
  PUBLIC_B = { id: "200", name: "test-2", public: true }.freeze
  PRIVATE_C = { id: "300", name: "admin-only", public: false }.freeze

  def setup
    RECENT_ACTIVITY.clear
  end

  def exchange(channel, question = "hi", answer = "hello", time: NOW, server: "1", speaker: ["5", "Piee"])
    record_recent_exchange(server, channel, speaker[0], speaker[1], question, answer, time)
  end

  def test_records_an_exchange_and_shows_it_in_other_channels
    exchange(PUBLIC_A, "explain Natlan", "Natlan is a land of fire")
    lines = recent_entries_for("1", PUBLIC_B[:id], NOW)
    assert_equal 1, lines.length
    assert_equal :exchange, lines[0][:kind]
    assert_equal ["test", "Piee", "explain Natlan", "Natlan is a land of fire"], lines[0].values_at(:channel_name, :speaker_name, :text, :answer)
  end

  def test_never_shows_the_current_channels_own_lines # Review Focus 3
    exchange(PUBLIC_A)
    assert_empty recent_entries_for("1", PUBLIC_A[:id], NOW)
  end

  def test_private_channel_lines_stay_in_that_channel # Review Focus 1
    exchange(PRIVATE_C, "ban X next week", "ok")
    assert_empty recent_entries_for("1", PUBLIC_B[:id], NOW)
    assert_equal 1, all_recent_entries("1", NOW).length # still in the log, only not shared
  end

  def test_old_lines_expire
    exchange(PUBLIC_A, time: NOW)
    later = NOW + (RECENT_ACTIVITY_HOURS * 3600) + 1
    assert_empty recent_entries_for("1", PUBLIC_B[:id], later)
    assert_empty all_recent_entries("1", later)
  end

  def test_one_busy_channel_keeps_at_most_8_lines # Review Focus 4
    exchange(PUBLIC_B, "only one in B", time: NOW - 60)
    30.times { |i| exchange(PUBLIC_A, "busy #{i}", time: NOW + i) }
    entries = all_recent_entries("1", NOW + 30)
    assert_equal RECENT_ACTIVITY_MAX_PER_CHANNEL, entries.count { |entry| entry[:channel_id] == PUBLIC_A[:id] }
    assert(entries.any? { |entry| entry[:text] == "only one in B" })
    assert_equal "busy 29", entries.last[:text] # the newest are kept, oldest first
  end

  def test_keeps_at_most_20_lines_in_total
    25.times { |i| exchange({ id: "c#{i}", name: "c#{i}", public: true }, "line #{i}", time: NOW + i) }
    entries = all_recent_entries("1", NOW + 25)
    assert_equal RECENT_ACTIVITY_MAX_LINES, entries.length
    assert_equal "line 5", entries.first[:text]
  end

  def test_cuts_long_text_to_one_short_line
    exchange(PUBLIC_A, "a\nb", "x" * (RECENT_ACTIVITY_ANSWER_CHARS + 50))
    entry = all_recent_entries("1", NOW).first
    assert_equal "a b", entry[:text]
    assert_equal RECENT_ACTIVITY_ANSWER_CHARS + 1, entry[:answer].length
    assert entry[:answer].end_with?("…")
  end

  def test_text_shows_exchanges_and_tags
    exchange(PUBLIC_A, "explain Natlan", "Natlan bở", time: Time.new(2026, 11, 11, 12, 14))
    record_recent_tag("1", PUBLIC_A, "1333", "Citlali [bot]", "hey @Cake, what's up?", Time.new(2026, 11, 11, 12, 20))
    text = recent_activity_text(recent_entries_for("1", PUBLIC_B[:id], NOW))
    assert_equal ["[12:14 #test] Piee (5) → you: \"explain Natlan\" — you: \"Natlan bở\"",
                  "[12:20 #test] Citlali [bot] (1333) tagged you: \"hey @Cake, what's up?\" (you did not answer)"], text.split("\n")
  end

  def test_forget_removes_a_persons_lines
    exchange(PUBLIC_A, "my lines", speaker: ["5", "Piee"])
    exchange(PUBLIC_A, "about <@5> and 5", speaker: ["6", "Pie"])
    exchange(PUBLIC_A, "someone else", speaker: ["7", "Bob"])
    forget_recent_activity_of("1", "5")
    assert_equal ["someone else"], all_recent_entries("1", NOW).map { |entry| entry[:text] }
  end

  def test_servers_are_separate
    exchange(PUBLIC_A, server: "1")
    assert_empty recent_entries_for("2", PUBLIC_B[:id], NOW)
  end

  def test_channel_info_comes_from_the_channel
    channel = Struct.new(:id, :name).new(100, "test") # no permission data: counts as private
    assert_equal({ id: "100", name: "test", public: false }, recent_channel_info(channel))
  end
end
