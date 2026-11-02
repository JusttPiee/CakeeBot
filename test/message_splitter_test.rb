require_relative "test_helper"
require_relative "../message_splitter"

class MessageSplitterTest < Minitest::Test
  def test_short_message_is_not_split
    assert_equal ["hello"], split_message("hello")
  end

  def test_long_message_is_split_under_the_limit
    text = "This is one line of a long reply.\n" * 200 # about 6,800 characters
    chunks = split_message(text)
    assert chunks.length > 1
    chunks.each { |chunk| assert chunk.length <= DISCORD_LIMIT }
  end

  def test_nothing_is_lost_when_splitting
    text = "This is one line of a long reply.\n" * 200
    assert_equal text, split_message(text).join
  end

  def test_splits_between_lines_not_inside_them
    text = "This is one line of a long reply.\n" * 200
    split_message(text).each { |chunk| assert chunk.end_with?("\n") }
  end

  def test_one_very_long_line_is_split_between_words
    text = "word " * 1_000 # 5,000 characters, no line breaks
    chunks = split_message(text)
    chunks.each { |chunk| assert chunk.length <= DISCORD_LIMIT }
    chunks[0...-1].each { |chunk| assert chunk.end_with?(" ") } # every cut happened at a space
    assert_equal text, chunks.join
  end

  def test_long_text_without_spaces_is_hard_cut
    text = "x" * 5_000 # like a very long URL
    chunks = split_message(text)
    chunks.each { |chunk| assert chunk.length <= DISCORD_LIMIT }
    assert_equal text, chunks.join
  end

  def test_empty_text_gives_no_messages
    assert_equal [], split_message("")
    assert_equal [], split_message("   \n")
  end
end
