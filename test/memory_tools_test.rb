require_relative "test_helper"
require "json"
require_relative "../config"
require_relative "../tool_list"

# The memory tools. The context (server, who is asking) always comes from the code, never from the AI.
class MemoryToolsTest < Minitest::Test
  CTX = { server_id: 1, requester_id: 123, requester_name: "Bach", channel_id: 555 }.freeze

  def setup
    clear_test_memory
    LOGS.clear
  end

  def test_remember_always_writes_to_the_requester
    run_tool("remember_about_me", '{"fact":"likes pho","user_id":"456"}', CTX)
    assert_equal 1, read_user_note(1, 123)[:remembered].length
    assert_nil read_user_note(1, 456)
  end

  def test_remember_confirms_whose_notes
    assert_equal "Saved to Bach's notes.", run_tool("remember_about_me", '{"fact":"likes pho"}', CTX)
  end

  def test_remember_rejects_too_long_facts
    assert_includes run_tool("remember_about_me", { fact: "a" * 501 }.to_json, CTX), "Error"
    assert_nil read_user_note(1, 123)
  end

  def test_remember_rejects_empty_facts
    assert_includes run_tool("remember_about_me", '{"fact":"  "}', CTX), "Error"
  end

  def test_remember_updates_the_index
    run_tool("remember_about_me", '{"fact":"likes pho"}', CTX)
    assert_includes read_memory_file(1, "MEMORY.md"), "Bach (123): likes pho"
  end

  def test_save_event_rejects_bad_dates
    assert_includes run_tool("save_event", '{"title":"Party","when":"saturday","details":""}', CTX), "must look like"
  end

  def test_save_event_updates_the_index
    result = run_tool("save_event", '{"title":"Valorant Cup","when":"2099-11-21 20:00","details":"x"}', CTX)
    assert_equal "Saved event: events/valorant-cup.md", result
    assert_includes read_memory_file(1, "MEMORY.md"), "Valorant Cup"
  end

  def test_read_memory_cannot_escape
    assert_includes run_tool("read_memory", '{"path":"../2/users/5.md"}', CTX), "Error"
  end

  def test_read_memory_reads_a_note
    append_remembered_fact(1, 123, "Bach", "likes pho")
    assert_includes run_tool("read_memory", '{"path":"users/123.md"}', CTX), "likes pho"
  end

  def test_read_memory_missing_file
    assert_includes run_tool("read_memory", '{"path":"users/999.md"}', CTX), "Error"
  end

  def test_no_server_means_no_memory
    assert_includes run_tool("remember_about_me", '{"fact":"x"}', {}), "not available"
    assert_includes run_tool("read_memory", '{"path":"users/1.md"}'), "not available"
  end

  def test_tool_calls_pass_the_context
    call = { "name" => "remember_about_me", "arguments" => '{"fact":"likes pho"}', "call_id" => "c1" }
    run_tool_calls([call], CTX)
    assert read_user_note(1, 123)
  end

  def test_read_memory_cannot_read_channel_summaries
    write_channel_summary(1, 999, "mod-only talk", 5)
    assert_includes run_tool("read_memory", '{"path":"channels/999.md"}', CTX), "Error"
  end
end
