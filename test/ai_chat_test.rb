require_relative "test_helper"
require "faraday"
require "tmpdir"
require_relative "../config"
require_relative "../ai_chat"

# A tool call that is safe in tests: localhost is blocked, so no real web request is made
def blocked_page_call(call_id = "call_1")
  { "type" => "function_call", "call_id" => call_id, "name" => "read_webpage",
    "arguments" => '{"url":"http://localhost/secret"}' }
end

# Pretends to be a Discord message event. Records everything the bot sends, and whether it was a reply.
class FakeEvent
  attr_reader :sent

  def initialize
    @sent = []
  end

  def message = self # event.message.reply! lands here too

  # Returns a pretend Discord message, like discordrb does. Its id is how many messages were sent so far.
  def reply!(text, mention_user:)
    @sent << { text: text, reply: true, ping: mention_user }
    Struct.new(:id).new(@sent.length)
  end

  def respond(text)
    @sent << { text: text, reply: false }
  end
end

class AiChatTest < Minitest::Test
  def setup
    LOGS.clear
  end

  def history
    [{ role: "user", content: "Bach (123): hello" }]
  end

  def test_system_prompt_goes_in_instructions_and_history_in_input
    client = FakeClient.new
    ask_ai(client, history, "Mochi")
    sent = client.requests.first
    assert_includes sent[:instructions], "Mochi"
    assert_equal [{ role: "user", content: "Bach (123): hello" }], sent[:input]
  end

  def test_conversation_is_not_stored_by_openai
    client = FakeClient.new
    ask_ai(client, history, "Mochi")
    assert_equal false, client.requests.first[:store]
    assert_includes client.requests.first[:include], "reasoning.encrypted_content"
  end

  # --- System prompt / personality ---

  def test_bot_name_is_filled_in
    prompt = build_system_prompt("Mochi")
    assert_includes prompt, "Mochi"
    refute_includes prompt, "{bot_name}"
  end

  def test_chat_rules_are_always_included
    assert_includes build_system_prompt("Mochi"), "Nickname (user_id)"
  end

  def test_personality_is_read_from_the_file
    Dir.mktmpdir do |dir|
      path = File.join(dir, "personality.txt")
      File.write(path, "You are {bot_name}, a pirate.")
      assert_equal "You are {bot_name}, a pirate.", load_personality(path)
    end
  end

  def test_missing_personality_file_uses_default
    Dir.mktmpdir do |dir|
      assert_equal default_personality, load_personality(File.join(dir, "personality.txt"))
    end
  end

  def test_missing_personality_file_is_generated
    Dir.mktmpdir do |dir|
      path = File.join(dir, "personality.txt")
      ensure_personality_file(path)
      assert_equal default_personality, File.read(path).strip
    end
  end

  def test_existing_personality_file_is_not_overwritten
    Dir.mktmpdir do |dir|
      path = File.join(dir, "personality.txt")
      File.write(path, "You are {bot_name}, a pirate.")
      ensure_personality_file(path)
      assert_equal "You are {bot_name}, a pirate.", File.read(path)
    end
  end

  def test_empty_personality_file_uses_default
    Dir.mktmpdir do |dir|
      path = File.join(dir, "personality.txt")
      File.write(path, "  \n") # only spaces and a blank line
      assert_equal default_personality, load_personality(path)
    end
  end

  def test_default_personality_uses_the_name_placeholder
    assert_includes default_personality, "{bot_name}"
  end

  # The command list lives in capabilities.txt, so it can't go stale in someone's local personality file
  def test_default_personality_has_no_command_list
    refute_includes default_personality, "!help"
  end

  def test_capabilities_are_always_included
    assert_includes build_system_prompt("Mochi"), "!help"
  end

  # --- Asking OpenAI ---

  def test_returns_the_ai_answer
    assert_equal "Hi Bach!", ask_ai(FakeClient.new, history, "Mochi")
  end

  def test_sends_settings_from_config
    client = FakeClient.new
    ask_ai(client, history, "Mochi")
    sent = client.requests.first
    assert_equal OPENAI_MODEL, sent[:model]
    assert_equal OPENAI_MAX_OUTPUT_TOKENS, sent[:max_output_tokens]
    assert_equal({ effort: OPENAI_REASONING_EFFORT }, sent[:reasoning])
  end

  def test_normal_answer_makes_only_one_request
    client = FakeClient.new
    ask_ai(client, history, "Mochi")
    assert_equal 1, client.requests.length
  end

  # The bug from 2026-11-03: the model spent the whole budget thinking and returned "" with no error.
  # Now it is logged, and the bot retries once without thinking.
  def test_empty_answer_retries_without_thinking
    client = FakeClient.new(answers: ["", "Here is your story"])
    assert_equal "Here is your story", ask_ai(client, history, "Mochi")
    assert_equal 2, client.requests.length
    assert_equal({ effort: OPENAI_FALLBACK_REASONING_EFFORT }, client.requests.last[:reasoning])
  end

  def test_empty_answer_is_logged_with_the_reason
    ask_ai(FakeClient.new(answers: ["", "ok"]), history, "Mochi")
    assert_includes LOGS.first, "reason: max_output_tokens"
    assert_includes LOGS.first, "reasoning: 4000"
  end

  def test_answer_text_joins_every_text_part
    response = { "output" => [
      { "type" => "reasoning" },
      { "type" => "message", "content" => [{ "type" => "output_text", "text" => "Hello " },
                                           { "type" => "output_text", "text" => "Bach" }] }
    ] }
    assert_equal "Hello Bach", answer_text(response)
  end

  def test_retries_only_once
    client = FakeClient.new(answers: ["", ""])
    assert_equal "", ask_ai(client, history, "Mochi")
    assert_equal 2, client.requests.length
  end

  # --- Tools ---

  def test_tools_are_offered_to_the_ai
    client = FakeClient.new
    ask_ai(client, history, "Mochi")
    names = client.requests.first[:tools].map { |tool| tool[:name] }
    assert_includes names, "read_webpage"
  end

  def test_tool_result_is_sent_back_and_the_ai_then_answers
    client = FakeClient.new(answers: [{ tool_calls: [blocked_page_call] }, "That link is blocked, sorry!"])
    assert_equal "That link is blocked, sorry!", ask_ai(client, history, "Mochi")
    assert_equal 2, client.requests.length

    tool_result = client.requests.last[:input].last
    assert_equal "function_call_output", tool_result[:type]
    assert_equal "call_1", tool_result[:call_id] # matches the AI's request
    assert_includes tool_result[:output], "blocked"
  end

  # The "tricky point": the AI's thinking from before the tool call must go back with the tool result
  def test_thinking_and_tool_request_are_sent_back_too
    client = FakeClient.new(answers: [{ tool_calls: [blocked_page_call] }, "ok"])
    ask_ai(client, history, "Mochi")
    types = client.requests.last[:input].map { |item| item["type"] || item[:type] || item[:role] }
    assert_equal %w[user reasoning function_call function_call_output], types
  end

  def test_tool_steps_are_not_saved_in_the_history
    saved = history
    ask_ai(FakeClient.new(answers: [{ tool_calls: [blocked_page_call] }, "ok"]), saved, "Mochi")
    assert_equal 1, saved.length
  end

  def test_stops_asking_for_tools_after_the_round_limit
    client = FakeClient.new(answers: [{ tool_calls: [blocked_page_call] }]) # always wants a tool
    ask_ai(client, history, "Mochi")
    last_request = client.requests[MAX_TOOL_ROUNDS] # rounds + 1 final "answer now" request
    assert_equal "none", last_request[:tool_choice]
  end

  def test_today_is_in_the_system_prompt
    assert_includes build_system_prompt("Mochi"), Date.today.year.to_s
  end

  # --- Sending the reply ---

  def test_short_answer_is_one_reply_without_ping
    event = FakeEvent.new
    send_reply(event, "Hi Bach!")
    assert_equal [{ text: "Hi Bach!", reply: true, ping: false }], event.sent
  end

  def test_every_chunk_of_a_long_answer_is_a_reply_without_ping
    event = FakeEvent.new
    send_reply(event, "A line of a long story.\n" * 300) # about 7,200 characters
    assert event.sent.length > 1
    event.sent.each do |message|
      assert message[:reply]
      refute message[:ping]
    end
  end

  def test_api_error_returns_nil_and_does_not_retry
    client = FakeClient.new(error: Faraday::ServerError.new("boom"))
    assert_nil ask_ai(client, history, "Mochi")
    assert_equal 1, client.requests.length
  end

  def test_send_reply_returns_the_last_sent_message
    assert_equal 1, send_reply(FakeEvent.new, "Hi Bach!").id
    assert_equal 2, send_reply(FakeEvent.new, "A line of a long story.
" * 120).id # two chunks
  end

  # --- Long-term memory in the prompt ---

  CONTEXT = { server_id: 1, requester_id: 123, requester_name: "Bach", channel_id: 555 }.freeze

  def test_memory_and_summary_go_into_instructions_in_order
    clear_test_memory
    write_user_personality(1, 123, "Bach", "x", "likes Valorant")
    write_channel_summary(1, 555, "We talked about pho.", 9)
    client = FakeClient.new
    ask_ai(client, history, "Mochi", CONTEXT)
    text = client.requests.first[:instructions]
    assert text.index("Today's date") < text.index("Bach (123): likes Valorant")
    assert text.index("likes Valorant") < text.index("We talked about pho.")
  end

  def test_mention_mode_gets_index_but_no_summary
    clear_test_memory
    write_user_personality(1, 123, "Bach", "x", "likes Valorant")
    write_channel_summary(1, 555, "secret summary", 9)
    client = FakeClient.new
    ask_ai(client, history, "Mochi", CONTEXT.merge(channel_id: nil))
    assert_includes client.requests.first[:instructions], "likes Valorant"
    refute_includes client.requests.first[:instructions], "secret summary"
  end

  def test_no_context_means_no_memory_sections
    refute_includes build_system_prompt("Mochi"), "Long-term memory"
    refute_includes build_system_prompt("Mochi"), "Summary of earlier"
  end

  def test_memory_rules_are_in_the_prompt
    assert_includes build_system_prompt("Mochi"), "never permissions"
  end

  def test_long_memory_is_cut_and_logged
    LOGS.clear
    assert_equal MEMORY_PROMPT_MAX_CHARS, cap_for_prompt("a" * 9_000, "Memory index").length
    assert_includes LOGS.last, "Memory index"
  end

  def test_short_memory_is_not_cut
    assert_equal "abc", cap_for_prompt("abc", "Memory index")
  end

  def test_tool_call_gets_the_context
    clear_test_memory
    call = { "type" => "function_call", "call_id" => "c1", "name" => "remember_about_me", "arguments" => '{"fact":"likes pho"}' }
    ask_ai(FakeClient.new(answers: [{ tool_calls: [call] }, "ok"]), history, "Mochi", CONTEXT)
    assert_equal 1, read_user_note(1, 123)[:remembered].length
  end

  def test_retry_without_thinking_keeps_the_memory
    clear_test_memory
    write_channel_summary(1, 555, "We talked about pho.", 9)
    client = FakeClient.new(answers: ["", "ok"])
    ask_ai(client, history, "Mochi", CONTEXT)
    assert_includes client.requests.last[:instructions], "We talked about pho."
  end
end
