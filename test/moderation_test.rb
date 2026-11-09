require_relative "test_helper"
require "json"
require_relative "../config"
require_relative "../tool_list"

# Pretends to be OpenAI's Moderation API: any text containing a word from `bad_words` is flagged as harassment.
class FakeModerationClient
  attr_reader :checked

  def initialize(bad_words: ["idiot"], error: nil)
    @bad_words = bad_words
    @error = error
    @checked = []
  end

  def moderations(parameters:)
    @checked << parameters[:input]
    raise @error if @error

    flagged = @bad_words.any? { |word| parameters[:input].include?(word) }
    { "results" => [{ "flagged" => flagged, "categories" => { "harassment" => flagged, "violence" => false } }] }
  end
end

# Memory tools check text with moderation before saving it
class ModerationTest < Minitest::Test
  def setup
    clear_test_memory
    LOGS.clear
    @client = FakeModerationClient.new
    @ctx = { server_id: 1, requester_id: 123, requester_name: "Bach", channel_id: 555, client: @client }
  end

  def test_flags_lists_the_flagged_categories
    assert_equal ["harassment"], moderation_flags(@client, "Pie is an idiot")
    assert_equal [], moderation_flags(@client, "Pie likes pho")
  end

  def test_no_client_skips_the_check
    assert_nil moderation_flags(nil, "Pie is an idiot")
  end

  def test_a_failed_check_allows_the_text_and_logs_it
    client = FakeModerationClient.new(error: Faraday::Error.new("down"))
    assert_nil moderation_flags(client, "Pie is an idiot")
    assert(LOGS.any? { |line| line.include?("Moderation check failed") })
  end

  def test_remember_about_me_refuses_harmful_text
    result = run_tool("remember_about_me", '{"fact":"thinks everyone is an idiot"}', @ctx)
    assert_includes result, "looks harmful"
    assert_nil read_user_note(1, 123)
    assert(LOGS.any? { |line| line.include?("harassment") })
  end

  def test_remember_about_me_saves_clean_text
    assert_equal "Saved to Bach's notes.", run_tool("remember_about_me", '{"fact":"likes pho"}', @ctx)
    assert_equal ["likes pho"], @client.checked
  end

  def test_why_and_how_are_checked_too
    result = run_tool("remember_about_me", '{"fact":"likes pho","why":"Pie is an idiot"}', @ctx)
    assert_includes result, "looks harmful"
  end

  def test_remember_about_someone_refuses_harmful_text
    result = run_tool("remember_about_someone", '{"user_id":"456","name":"Pie","note":"is an idiot"}', @ctx)
    assert_includes result, "looks harmful"
    assert_empty general_memory_items(1)
  end

  def test_update_memory_refuses_harmful_text
    append_remembered_fact(1, 123, "Bach", "likes pho")
    id = personal_memory_items(1).first[:id]
    result = run_tool("update_memory", { memory_id: id, new_text: "is an idiot" }.to_json, @ctx)
    assert_includes result, "looks harmful"
    assert_equal "likes pho", personal_memory_items(1).first[:text]
  end

  def test_save_event_refuses_harmful_details
    args = { title: "Cup", when: "2099-11-21", details: "beat the idiot" }.to_json
    assert_includes run_tool("save_event", args, @ctx), "looks harmful"
    assert_empty list_memory_files(1, "events")
  end

  def test_update_my_personality_refuses_harmful_text
    result = run_tool("update_my_personality", '{"new_text":"an idiot","description":"x"}', @ctx)
    assert_includes result, "looks harmful"
  end
end
