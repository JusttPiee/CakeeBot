require_relative "test_helper"
require_relative "../notes_file"

# The shared file format for memory notes: "key: value" header lines, a blank line, then the text.
class NotesFileTest < Minitest::Test
  def test_round_trip
    text = format_note({ "title" => "Valorant", "when" => "2026-11-21 20:00" }, "Bring snacks")
    assert_equal "title: Valorant\nwhen: 2026-11-21 20:00\n\nBring snacks\n", text
    assert_equal({ headers: { "title" => "Valorant", "when" => "2026-11-21 20:00" }, body: "Bring snacks" },
                 parse_note(text))
  end

  def test_text_without_headers_is_all_body
    assert_equal({ headers: {}, body: "just some notes\nmore" }, parse_note("just some notes\nmore"))
  end

  def test_header_values_may_contain_colons
    note = parse_note("description: Bach (123): likes Valorant\n\nx")
    assert_equal "Bach (123): likes Valorant", note[:headers]["description"]
  end

  def test_empty_text
    assert_equal({ headers: {}, body: "" }, parse_note(""))
  end

  def test_header_values_stay_on_one_line
    assert_equal "title: a b\n\n\n", format_note({ "title" => "a\nb" }, "")
  end

  def test_byte_order_mark_is_ignored
    assert_equal "Cup", parse_note("﻿title: Cup\n\nx")[:headers]["title"] # some editors add this mark
  end
end
