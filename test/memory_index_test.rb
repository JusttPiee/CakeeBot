require_relative "test_helper"
require_relative "../memory_index"

# MEMORY.md: the list of saved notes that goes into every prompt. Built by code, never by the AI.
class MemoryIndexTest < Minitest::Test
  NOW = Time.new(2026, 11, 10, 12, 0)

  def setup
    clear_test_memory
  end

  def test_upcoming_events_and_people_are_listed
    save_event_note(1, "Valorant Cup", "2026-11-21 20:00", "")
    write_user_personality(1, 123, "Bach", "x", "likes Valorant")
    text = rebuild_memory_index(1, NOW)
    assert_includes text, "## Upcoming events\n- events/valorant-cup.md"
    assert_includes text, "## People\n- users/123.md: Bach (123): likes Valorant"
    assert_equal text, read_memory_file(1, "MEMORY.md")
  end

  def test_past_event_is_hidden_but_never_deleted
    save_event_note(1, "Ancient Party", "2026-01-01", "")
    refute_includes rebuild_memory_index(1, NOW), "Ancient Party"
    assert_equal 1, list_event_notes(1).length
  end

  def test_empty_server_gives_empty_text_and_no_folder
    assert_equal "", rebuild_memory_index(42, NOW)
    refute Dir.exist?(server_memory_dir(42))
  end

  def test_hand_edited_garbage_file_does_not_crash
    write_memory_file(1, "users/77.md", "random text, no headers")
    write_memory_file(1, "events/broken.md", "no when here")
    text = rebuild_memory_index(1, NOW)
    assert_includes text, "users/77.md"
    refute_includes text, "broken"
  end

  def test_only_people_and_no_events
    append_remembered_fact(1, 123, "Bach", "likes pho")
    assert_equal "## People\n- users/123.md: Bach (123): likes pho\n", rebuild_memory_index(1, NOW)
  end

  def test_note_with_a_bad_file_name_is_skipped
    path = File.join(MEMORY_DIR, "1", "users", "a..b.md")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "name: Weird\n\nx")
    append_remembered_fact(1, 123, "Bach", "likes pho")
    text = rebuild_memory_index(1, NOW)
    assert_includes text, "Bach (123)"
    refute_includes text, "Weird"
  end
end
