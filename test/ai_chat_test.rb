require_relative "test_helper"
require "faraday"
require "tmpdir"
require_relative "../config"
require_relative "../ai_chat"

# Pretends to be OpenAI's Responses API (no real API call, no cost). Used as client.responses.create(...)
# Give it a list of answers: the 1st request gets the 1st answer, the 2nd request the 2nd, and so on.
# It remembers every request it received in `requests`.
class FakeClient
  attr_reader :requests

  def initialize(answers: ["Hi Bach!"], error: nil)
    @answers = answers
    @error = error
    @requests = []
  end

  def responses = self # client.responses.create lands on create below

  # An answer can be text, or { tool_calls: [...] } to pretend the AI thought and then asked for tools
  def create(parameters:)
    @requests << Marshal.load(Marshal.dump(parameters)) # a copy, so later changes to input don't show up here
    raise @error if @error
    answer = @answers[[@requests.length - 1, @answers.length - 1].min] # the last answer repeats
    return tool_call_response(answer[:tool_calls]) if answer.is_a?(Hash)
    return empty_response if answer == ""

    { "status" => "completed",
      "output" => [{ "type" => "message", "content" => [{ "type" => "output_text", "text" => answer }] }] }
  end

  # What OpenAI sends when the model used every token on thinking: no message, status "incomplete"
  def empty_response
    { "status" => "incomplete", "incomplete_details" => { "reason" => "max_output_tokens" },
      "output" => [{ "type" => "reasoning", "encrypted_content" => "locked-thinking" }],
      "usage" => { "output_tokens" => 4000, "output_tokens_details" => { "reasoning_tokens" => 4000 } } }
  end

  def tool_call_response(tool_calls)
    { "status" => "completed",
      "output" => [{ "type" => "reasoning", "encrypted_content" => "locked-thinking" }] + tool_calls }
  end
end

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

  def reply!(text, mention_user:)
    @sent << { text: text, reply: true, ping: mention_user }
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
    assert_equal DEFAULT_PERSONALITY, load_personality("no/such/file.txt")
  end

  def test_empty_personality_file_uses_default
    Dir.mktmpdir do |dir|
      path = File.join(dir, "personality.txt")
      File.write(path, "  \n") # only spaces and a blank line
      assert_equal DEFAULT_PERSONALITY, load_personality(path)
    end
  end

  def test_shipped_personality_file_uses_the_name_placeholder
    assert_includes load_personality, "{bot_name}"
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
end
