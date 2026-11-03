require_relative "test_helper"
require_relative "../event_notes"

# Planned events with a date: memory/<server_id>/events/<slug>.md
class EventNotesTest < Minitest::Test
  def setup
    clear_test_memory
  end

  def test_valid_and_invalid_times
    assert parse_event_time("2026-11-21")
    assert parse_event_time("2026-11-21 20:00")
    assert_nil parse_event_time("next saturday")
    assert_nil parse_event_time("2026-02-30")
    assert_nil parse_event_time("2026-11-21 8pm")
    assert_nil parse_event_time("2026-11-21 25:00")
  end

  def test_vietnamese_slug
    assert_equal "giải-đấu-valorant", event_slug("Giải đấu Valorant!")
    assert_equal "event", event_slug("!!!")
  end

  def test_long_titles_give_short_slugs
    assert event_slug("a" * 200).length <= 50
  end

  def test_save_and_list
    assert_equal "events/valorant-cup.md", save_event_note(1, "Valorant Cup", "2026-11-21 20:00", "Bach hosts")
    assert_equal [{ path: "events/valorant-cup.md", title: "Valorant Cup", when: "2026-11-21 20:00", details: "Bach hosts" }],
                 list_event_notes(1)
  end

  def test_invalid_time_is_not_saved
    assert_nil save_event_note(1, "Party", "soon", "")
    assert_equal [], list_event_notes(1)
  end

  def test_same_title_overwrites
    save_event_note(1, "Valorant Cup", "2026-11-21", "old")
    save_event_note(1, "Valorant Cup", "2026-11-22", "new")
    assert_equal ["2026-11-22"], list_event_notes(1).map { |event| event[:when] }
  end

  def test_files_without_a_valid_date_are_skipped
    write_memory_file(1, "events/broken.md", "no when here")
    assert_equal [], list_event_notes(1)
  end

  def test_date_only_event_is_past_only_after_that_day
    refute event_past?("2026-11-21", Time.new(2026, 11, 21, 23, 0))
    assert event_past?("2026-11-21", Time.new(2026, 11, 22, 0, 1))
  end

  def test_timed_event_is_past_after_its_time
    refute event_past?("2026-11-21 20:00", Time.new(2026, 11, 21, 19, 59))
    assert event_past?("2026-11-21 20:00", Time.new(2026, 11, 21, 20, 1))
  end

  def test_index_line
    event = { path: "events/valorant-cup.md", title: "Valorant Cup", when: "2026-11-21 20:00", details: "" }
    assert_equal "- events/valorant-cup.md: Valorant Cup, Sat 2026-11-21 20:00", event_index_line(event)
    event[:when] = "2026-11-21"
    assert_equal "- events/valorant-cup.md: Valorant Cup, Sat 2026-11-21", event_index_line(event)
  end
end
