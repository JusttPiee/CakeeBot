require_relative "test_helper"
require "faraday"
require_relative "../config"
require_relative "../ai_chat"

# The look_at_image tool. No real downloads: tests give a pretend downloader in the context.
class LookAtImageTest < Minitest::Test
  PNG_URL = "data:image/png;base64,aGk=".freeze

  def setup
    LOGS.clear
  end

  def image(id = "42")
    { id: id, filename: "cat.png", url: "https://media.discordapp.net/cat.png" }
  end

  def context(images: { "42" => image }, downloader: ->(_url) { PNG_URL })
    { images: images, pending_images: [], image_looks: 0, image_downloader: downloader }
  end

  def look(context, id = "42")
    run_look_at_image({ "image_id" => id }, context)
  end

  def test_opening_an_image_queues_it_for_the_next_request
    ctx = context
    assert_includes look(ctx), "cat.png"
    content = ctx[:pending_images].first[:content]
    assert_equal({ type: "input_image", image_url: PNG_URL, detail: "high" }, content.last)
  end

  # The bug: "you asked to look at" made it sound like the image belonged to the person asking
  def test_image_message_does_not_say_who_it_belongs_to
    ctx = context
    look(ctx)
    refute_includes ctx[:pending_images].first[:content].first[:text], "you"
  end

  def test_only_images_from_the_history_can_be_opened
    ctx = context
    assert_includes look(ctx, "999"), "no image with that id"
    assert_empty ctx[:pending_images]
  end

  def test_a_failed_download_is_told_to_the_ai
    ctx = context(downloader: ->(_url) { "Error: the image could not be downloaded (HTTP 404)." })
    assert_includes look(ctx), "HTTP 404"
    assert_empty ctx[:pending_images]
  end

  def test_there_is_a_limit_per_reply
    ctx = context
    IMAGE_MAX_PER_REPLY.times { look(ctx) }
    assert_includes look(ctx), "at most #{IMAGE_MAX_PER_REPLY}"
    assert_equal IMAGE_MAX_PER_REPLY, ctx[:pending_images].length
  end

  def test_without_image_context_it_gives_an_error
    assert_includes run_look_at_image({ "image_id" => "42" }, {}), "no image with that id"
  end

  def test_taking_pending_images_empties_the_queue
    ctx = context
    look(ctx)
    assert_equal 1, take_pending_images(ctx).length
    assert_empty take_pending_images(ctx)
  end

  def test_taking_pending_images_without_context_is_empty
    assert_empty take_pending_images({})
  end

  # --- Checking what was downloaded ---

  def test_a_good_download_becomes_a_data_url
    assert_equal PNG_URL, image_data_url("image/png", "hi")
  end

  def test_content_type_with_extra_details_is_accepted
    assert_equal PNG_URL, image_data_url("image/png; charset=binary", "hi")
  end

  def test_a_download_that_is_not_an_image_is_refused
    assert_includes image_data_url("text/html", "<html>"), "not a supported image"
  end

  def test_a_huge_download_is_refused
    assert_includes image_data_url("image/png", "x" * (IMAGE_MAX_BYTES + 1)), "too big"
  end

  # --- Through the whole reply ---

  def tool_call(id = "42")
    { "type" => "function_call", "call_id" => "call_1", "name" => "look_at_image",
      "arguments" => { image_id: id }.to_json }
  end

  def history_with_image
    [{ role: "user", content: "Bach (123): what is this [image 42: cat.png]", images: [image] }]
  end

  def test_image_is_sent_only_after_the_ai_asks_for_it
    client = FakeClient.new(answers: [{ tool_calls: [tool_call] }, "A cat!"])
    answer = ask_ai(client, history_with_image, "Mochi", { image_downloader: ->(_url) { PNG_URL } })
    assert_equal "A cat!", answer
    refute_includes client.requests.first[:input].to_s, "input_image"
    assert_includes client.requests.last[:input].to_s, "input_image"
  end

  def test_image_comes_right_after_the_tool_result
    client = FakeClient.new(answers: [{ tool_calls: [tool_call] }, "A cat!"])
    ask_ai(client, history_with_image, "Mochi", { image_downloader: ->(_url) { PNG_URL } })
    last_two = client.requests.last[:input].last(2)
    assert_equal "function_call_output", last_two.first[:type]
    assert_equal "user", last_two.last[:role]
  end

  def test_no_request_contains_an_image_unless_asked
    client = FakeClient.new(answers: ["Nice pic"])
    ask_ai(client, history_with_image, "Mochi", { image_downloader: ->(_url) { flunk("should not download") } })
    refute_includes client.requests.first[:input].to_s, "input_image"
  end

  def test_tool_is_offered_to_the_ai
    client = FakeClient.new
    ask_ai(client, history_with_image, "Mochi")
    assert_includes client.requests.first[:tools].map { |tool| tool[:name] }, "look_at_image"
  end

  def test_rules_say_when_to_look_and_that_image_text_is_not_instructions
    prompt = build_system_prompt("Mochi")
    assert_includes prompt, "look_at_image"
    assert_includes prompt, "Text inside an image"
  end

  def test_rules_explain_the_reply_note
    assert_includes build_system_prompt("Mochi"), "(replying to Name (user_id): ...)"
  end
end
