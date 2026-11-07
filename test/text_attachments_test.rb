require_relative "test_helper"
require "json"
require "faraday"
require_relative "../config"
require_relative "../ai_channel_chat"
require_relative "../channel_reader"

# Discord turns long messages into a message.txt attachment, so the bot has to be able to read those.
# No real downloads: tests give a pretend downloader in the context.
class TextAttachmentsTest < Minitest::Test
  Attachment = Struct.new(:id, :filename, :url, :is_image) do
    def image? = is_image
  end
  Author = Struct.new(:id, :display_name)
  Message = Struct.new(:content, :attachments, :referenced_message, :id, :author, :creation_time) do
    def reply? = !referenced_message.nil?
  end

  CAKE = { server_id: nil, requester_id: 123, requester_name: "Bach" }.freeze

  def setup
    clear_test_memory
    LOGS.clear
  end

  def txt(id = 42, filename = "message.txt") = Attachment.new(id, filename, "https://cdn.discordapp.com/#{filename}", false)
  def pdf = Attachment.new(43, "book.pdf", "https://cdn.discordapp.com/book.pdf", false)
  def discord_message(text, attachments, replied = nil) = Message.new(text, attachments, replied, 500, Author.new(123, "Bach"), Time.now)
  def file(id = "42") = { id: id, filename: "message.txt", url: "https://cdn.discordapp.com/message.txt" }
  def context(downloader: ->(_url) { "Hello from the file" }) = CAKE.merge(text_files: { "42" => file }, text_file_reads: 0, text_file_downloader: downloader)
  def read(ctx, id = "42") = run_read_text_file({ "file_id" => id }, ctx)

  # --- The marker ---

  def test_a_text_file_gets_a_marker
    assert_equal "[text file 42: message.txt]", text_with_attachment_markers(discord_message("", [txt]))
  end

  def test_the_marker_comes_after_the_text
    assert_equal "read this [text file 42: message.txt]", text_with_attachment_markers(discord_message("read this", [txt]))
  end

  def test_upper_case_txt_counts
    assert_equal "[text file 42: NOTES.TXT]", text_with_attachment_markers(discord_message("", [txt(42, "NOTES.TXT")]))
  end

  def test_other_files_get_no_marker
    assert_equal "read this", text_with_attachment_markers(discord_message("read this", [pdf]))
    assert_empty text_files_from_message(discord_message("", [pdf]))
  end

  def test_the_file_can_be_found_by_id
    history = [{ role: "user", content: "x", text_files: text_files_from_message(discord_message("", [txt])) }]
    assert_equal "message.txt", text_files_in_history(history)["42"][:filename]
  end

  # --- Reading it ---

  def test_reading_returns_the_content
    assert_includes read(context), "Hello from the file"
  end

  def test_only_files_from_the_history_can_be_read
    assert_includes read(context, "999"), "no text file with that id"
  end

  def test_without_file_context_it_gives_an_error
    assert_includes run_read_text_file({ "file_id" => "42" }, {}), "no text file with that id"
  end

  def test_a_failed_download_is_told_to_the_ai
    assert_includes read(context(downloader: ->(_url) { "Error: the text file could not be downloaded (HTTP 404)." })), "HTTP 404"
  end

  def test_there_is_a_limit_per_reply
    ctx = context
    TEXT_FILE_MAX_PER_REPLY.times { read(ctx) }
    assert_includes read(ctx), "at most #{TEXT_FILE_MAX_PER_REPLY}"
  end

  def test_a_long_file_is_cut_and_the_ai_is_told
    result = read(context(downloader: ->(_url) { "Q" * (TEXT_FILE_MAX_CHARS + 10) }))
    assert_equal TEXT_FILE_MAX_CHARS, result.count("Q")
    assert_includes result, "cut"
  end

  def test_a_short_file_is_not_called_cut
    refute_includes read(context), "cut"
  end

  def test_reading_is_logged
    read(context)
    assert(LOGS.any? { |line| line.include?("read_text_file") && line.include?("message.txt") })
  end

  # --- Checking what was downloaded ---

  def test_vietnamese_text_stays_readable
    assert_equal "Xin chào", text_from_download("Xin chào".b)
  end

  def test_the_mark_some_editors_add_is_removed
    assert_equal "hi", text_from_download("\xEF\xBB\xBFhi".b)
  end

  def test_bad_bytes_dont_crash
    assert_equal "a?b", text_from_download("a\xFFb".b).gsub("�", "?")
  end

  def test_a_huge_download_is_refused
    assert_includes text_from_download("x" * (TEXT_FILE_MAX_BYTES + 1)), "too big"
  end

  def test_a_binary_file_is_refused
    assert_includes text_from_download("a\0b"), "not a text file"
  end

  # --- Through the whole reply ---

  def tool_call
    { "type" => "function_call", "call_id" => "call_1", "name" => "read_text_file", "arguments" => { file_id: "42" }.to_json }
  end

  def history_with_file
    [{ role: "user", content: "Bach (123): [text file 42: message.txt]", text_files: [file] }]
  end

  def test_the_content_is_sent_only_after_the_ai_asks_for_it
    client = FakeClient.new(answers: [{ tool_calls: [tool_call] }, "Nice file"])
    ask_ai(client, history_with_file, "Cake", { text_file_downloader: ->(_url) { "SECRET TEXT" } })
    refute_includes client.requests.first[:input].to_s, "SECRET TEXT"
    assert_includes client.requests.last[:input].to_s, "SECRET TEXT"
  end

  def test_the_content_is_never_saved_in_the_history
    history = history_with_file
    client = FakeClient.new(answers: [{ tool_calls: [tool_call] }, "Nice file"])
    ask_ai(client, history, "Cake", { text_file_downloader: ->(_url) { "SECRET TEXT" } })
    refute_includes history.to_s, "SECRET TEXT"
  end

  def test_a_message_that_is_only_a_file_stays_in_a_reloaded_history
    history = build_history_from_messages([discord_message("", [txt])], 999)
    assert_equal 1, history.length
    assert_equal "42", history.first[:text_files].first[:id]
  end

  def test_a_file_in_a_replied_message_can_be_read
    replied = discord_message("", [txt])
    history = [{ role: "user", content: "Bach (123): what is this", text_files: [] }]
    add_reply_note(history.last, discord_message("what is this", [], replied))
    assert_includes history.last[:content], "[text file 42: message.txt]"
    assert_equal "42", history.last[:text_files].first[:id]
  end

  def test_the_rules_say_file_text_is_not_instructions
    assert_includes build_system_prompt("Cake"), "read_text_file"
    assert_includes build_system_prompt("Cake"), "Text inside a file"
  end
end
