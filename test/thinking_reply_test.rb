require_relative "test_helper"
require_relative "../config"
require_relative "../thinking_reply"

# A sent Discord message that remembers its edits. edit_fails: true makes the edit raise, like a deleted message.
# Only edit_without_ping exists: a plain edit would ping the person again (see message_edit.rb).
class FakeThinkingMessage
  attr_reader :id, :edits

  def initialize(id, edit_fails: false)
    @id = id
    @edit_fails = edit_fails
    @edits = []
  end

  def edit_without_ping(text)
    raise "Unknown Message" if @edit_fails

    @edits << text
    self
  end
end

# Only what deliver_answer and send_thinking use: event.message.reply!
class FakeThinkingEvent
  attr_reader :replies

  def initialize(reply_fails: false)
    @replies = []
    @reply_fails = reply_fails
  end

  def message = self

  def reply!(text, mention_user:)
    raise "Missing Access" if @reply_fails

    @replies << text
    FakeThinkingMessage.new(100 + @replies.length)
  end
end

class ThinkingReplyTest < Minitest::Test
  def setup
    FileUtils.rm_f(File.join(MEMORY_DIR, "t.json"))
    LOGS.clear
  end

  # A library with one emoji, notes in a test file
  def library_named(name, id)
    EmojiLibrary.new(notes_path: File.join(MEMORY_DIR, "t.json")).tap do |library|
      library.refresh(-> { [{ id: id, name: name, animated: false }] })
    end
  end

  def event_with_thinking(edit_fails: false)
    [FakeThinkingEvent.new, FakeThinkingMessage.new(77, edit_fails: edit_fails)]
  end

  def test_thinking_uses_the_emoji_or_falls_back
    assert_equal "<:thinking:9> Thinking...", thinking_text(library_named("thinking", 9))
    assert_equal "🤔 Thinking...", thinking_text(EmojiLibrary.new(notes_path: File.join(MEMORY_DIR, "t.json")))
  end

  def test_send_thinking_replies_without_ping
    event = FakeThinkingEvent.new
    message = send_thinking(event, library_named("x", 1))
    assert_equal ["🤔 Thinking..."], event.replies
    assert_equal 101, message.id
  end

  def test_failed_thinking_gives_nil_and_logs
    assert_nil send_thinking(FakeThinkingEvent.new(reply_fails: true), library_named("x", 1))
    assert(LOGS.any? { |line| line.start_with?("😀 ") })
  end

  def test_answer_is_edited_into_thinking_and_converted
    event, thinking = event_with_thinking
    sent = deliver_answer(event, thinking, "yay :thinking:", library_named("thinking", 9))
    assert_equal ["yay <:thinking:9>"], thinking.edits
    assert_empty event.replies
    assert_same thinking, sent
  end

  def test_long_answer_edits_first_chunk_and_sends_rest
    event, thinking = event_with_thinking
    sent = deliver_answer(event, thinking, "a\n" * 2000, library_named("x", 1))
    assert_equal 1, thinking.edits.length
    refute_empty event.replies
    assert_equal 100 + event.replies.length, sent.id # the last message sent
  end

  # The 2000-character limit is about the converted text: 1000 ":ok:" become 1000 "<:ok:1>"
  def test_splitting_happens_after_converting
    event, thinking = event_with_thinking
    deliver_answer(event, thinking, ":ok: " * 1000, library_named("ok", 1))
    all = thinking.edits + event.replies
    assert(all.all? { |chunk| chunk.length <= DISCORD_LIMIT })
    assert_equal "<:ok:1> " * 1000, all.join # converted, nothing lost
  end

  def test_failed_edit_falls_back_to_reply
    event, thinking = event_with_thinking(edit_fails: true)
    sent = deliver_answer(event, thinking, "hello", library_named("x", 1))
    assert_equal ["hello"], event.replies
    assert_equal 101, sent.id
  end

  def test_without_thinking_every_chunk_is_a_reply
    event = FakeThinkingEvent.new
    deliver_answer(event, nil, "hello", library_named("x", 1))
    assert_equal ["hello"], event.replies
  end

  def test_emoji_chunks_convert_count_and_split
    lib = library_named("ok", 1)
    chunks = emoji_chunks(":ok: " * 1000, lib)
    assert_equal "<:ok:1> " * 1000, chunks.join
    assert_operator chunks.length, :>, 1
    assert_equal 1000, lib.entries.first.uses
  end

  def test_with_thinking_turns_a_crash_into_unavailable
    event = FakeThinkingEvent.new
    thinking = nil
    assert_raises(RuntimeError) do
      with_thinking(event) do |message|
        thinking = message
        raise "boom"
      end
    end
    assert_equal ["🤔 Thinking..."], event.replies
    assert_equal [AI_UNAVAILABLE_MESSAGE], thinking.edits
  end

  def test_with_thinking_gives_the_block_result
    assert_equal :ok, with_thinking(FakeThinkingEvent.new) { :ok }
  end

  # Counting uses is an extra: if it breaks, the answer still goes out, converted
  def test_failed_use_count_still_delivers
    lib = library_named("ok", 1)
    def lib.record_uses(_text) = raise(ArgumentError, "broken notes")
    event, thinking = event_with_thinking
    deliver_answer(event, thinking, "hi :ok:", lib)
    assert_equal ["hi <:ok:1>"], thinking.edits
    assert(LOGS.any? { |line| line.start_with?("😀 ") })
  end

  def test_uses_counted_from_the_ai_text
    lib = library_named("thinking", 9)
    event, thinking = event_with_thinking
    deliver_answer(event, thinking, ":thinking: :thinking:", lib)
    assert_equal 2, lib.entries.first.uses
  end
end
