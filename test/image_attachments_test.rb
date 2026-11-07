require_relative "test_helper"
require_relative "../config"
require_relative "../chat_history"
require_relative "../image_attachments"

# Images people post: the AI only gets a small text marker, the picture itself is opened later by a tool.
class ImageAttachmentsTest < Minitest::Test
  FakeAttachment = Struct.new(:id, :filename, :proxy_url, :url, :width, :height, :content_type) do
    def image? = !width.nil? && !height.nil?
  end
  FakeAuthor = Struct.new(:display_name, :id)
  FakeMessage = Struct.new(:content, :attachments, :referenced_message, :author) do
    def reply? = !referenced_message.nil?
  end
  B = FakeAuthor.new("b", 777)

  PROXY = "https://media.discordapp.net/attachments/1/2/cat.png?ex=abc&is=def&hm=123&".freeze

  def setup
    LOGS.clear
  end

  def png(id: 42, width: 800, height: 600)
    FakeAttachment.new(id, "cat.png", PROXY, "https://cdn.discordapp.com/cat.png", width, height, "image/png")
  end

  def gif
    FakeAttachment.new(7, "dance.gif", PROXY, "https://cdn.discordapp.com/dance.gif", 100, 100, "image/gif")
  end

  def pdf
    FakeAttachment.new(8, "notes.pdf", PROXY, "https://cdn.discordapp.com/notes.pdf", nil, nil, "application/pdf")
  end

  # --- Markers in the text ---

  def test_marker_is_added_after_the_message_text
    message = FakeMessage.new("look", [png])
    assert_equal "look [image 42: cat.png]", text_with_image_markers(message)
  end

  def test_message_with_only_an_image_still_has_text
    assert_equal "[image 42: cat.png]", text_with_image_markers(FakeMessage.new("", [png]))
  end

  def test_message_without_attachments_keeps_its_text
    assert_equal "hello", text_with_image_markers(FakeMessage.new(" hello ", []))
  end

  def test_gif_marker_says_it_cannot_be_viewed
    assert_equal "[dance.gif: this image type can't be viewed]", text_with_image_markers(FakeMessage.new("", [gif]))
  end

  def test_files_that_are_not_images_get_no_marker
    assert_equal "read this", text_with_image_markers(FakeMessage.new("read this", [pdf]))
  end

  # --- Which images can be opened ---

  def test_only_viewable_images_are_listed
    images = images_from_message(FakeMessage.new("", [png, gif, pdf]))
    assert_equal ["42"], images.map { |image| image[:id] }
  end

  def test_jpeg_and_webp_are_viewable
    %w[image/jpeg image/webp].each do |type|
      attachment = png
      attachment.content_type = type
      assert_equal 1, images_from_message(FakeMessage.new("", [attachment])).length
    end
  end

  # --- Size (about 0.012 cents per image) ---

  def test_big_image_is_scaled_down_to_the_max_side
    url = resized_image_url(PROXY, 2048, 1024)
    assert_equal "https://media.discordapp.net/attachments/1/2/cat.png?ex=abc&is=def&hm=123&width=1024&height=512", url
  end

  def test_tall_image_is_limited_by_its_height
    assert_includes resized_image_url(PROXY, 500, 2000), "width=256&height=1024"
  end

  def test_small_image_keeps_its_size
    assert_equal PROXY, resized_image_url(PROXY, 800, 600)
  end

  def test_url_without_a_query_gets_one
    assert_equal "https://x.test/a.png?width=1024&height=1024", resized_image_url("https://x.test/a.png", 2048, 2048)
  end

  # --- History ---

  def test_images_are_kept_in_the_history_but_not_sent_as_text
    history = []
    add_user_message(history, "Bach", 123, "[image 42: cat.png]", Time.now, images: images_from_message(FakeMessage.new("", [png])))
    assert_equal "42", history.first[:images].first[:id]
    assert_equal %i[content role], format_history_for_openai(history).first.keys.sort
  end

  def test_images_in_history_can_be_found_by_id
    history = []
    add_user_message(history, "Bach", 123, "a", Time.now, images: images_from_message(FakeMessage.new("", [png(id: 1)])))
    add_user_message(history, "Bach", 123, "no image", Time.now)
    add_assistant_message(history, "nice")
    add_user_message(history, "Bach", 123, "b", Time.now, images: images_from_message(FakeMessage.new("", [png(id: 2)])))
    assert_equal %w[1 2], images_in_history(history).keys
  end

  # --- Replying to a message with an image ---

  def entry_after_reply(replied)
    history = []
    add_user_message(history, "Bach", 123, "what is this", Time.now)
    add_reply_note(history.last, FakeMessage.new("what is this", [], replied))
    history.last
  end

  # The bug: the AI said "you" about b's picture, because the note didn't say whose message it was
  def test_reply_note_says_who_posted_the_image
    entry = entry_after_reply(FakeMessage.new("", [png], nil, B))
    assert_equal "Bach (123): what is this (replying to b (777): [image 42: cat.png])", entry[:content]
  end

  def test_replying_to_an_image_lets_the_ai_open_it
    entry = entry_after_reply(FakeMessage.new("", [png], nil, B))
    assert_equal ["42"], entry[:images].map { |image| image[:id] }
  end

  def test_reply_note_quotes_the_text_of_the_message
    entry = entry_after_reply(FakeMessage.new("gg ez", [], nil, B))
    assert_includes entry[:content], "(replying to b (777): gg ez)"
  end

  def test_long_quote_is_cut_but_the_image_marker_stays
    entry = entry_after_reply(FakeMessage.new("x" * 500, [png], nil, B))
    assert_includes entry[:content], "#{'x' * REPLY_QUOTE_MAX_CHARS}... [image 42: cat.png])"
    refute_includes entry[:content], "x" * (REPLY_QUOTE_MAX_CHARS + 1)
  end

  def test_message_that_is_not_a_reply_changes_nothing
    history = []
    add_user_message(history, "Bach", 123, "ok", Time.now)
    add_reply_note(history.last, FakeMessage.new("ok", []))
    assert_equal "Bach (123): ok", history.last[:content]
  end

  def test_a_failure_reading_the_replied_message_is_only_logged
    message = Object.new
    def message.reply? = raise(IOError, "discord down")
    history = []
    add_user_message(history, "Bach", 123, "what", Time.now)
    add_reply_note(history.last, message)
    assert_includes LOGS.last, "IOError"
  end
end
