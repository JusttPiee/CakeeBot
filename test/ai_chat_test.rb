require "minitest/autorun"
require "faraday"
require "tmpdir"
require_relative "../config"
require_relative "../ai_chat"

# log and describe_openai_error normally come from cakee.rb
LOGS = []
def log(message) = LOGS << message
def describe_openai_error(_error) = "fake error"

# Pretends to be OpenAI (no real API call, no cost).
# Give it a list of answers: the 1st request gets the 1st answer, the 2nd request the 2nd, and so on.
# It remembers every request it received in `requests`.
class FakeClient
  attr_reader :requests

  def initialize(answers: ["Hi Bach!"], error: nil)
    @answers = answers
    @error = error
    @requests = []
  end

  def chat(parameters:)
    @requests << parameters
    raise @error if @error
    answer = @answers[@requests.length - 1]
    {
      "choices" => [{ "message" => { "content" => answer }, "finish_reason" => answer == "" ? "length" : "stop" }],
      "usage" => { "completion_tokens" => 4000, "completion_tokens_details" => { "reasoning_tokens" => 4000 } }
    }
  end
end

class AiChatTest < Minitest::Test
  def setup
    LOGS.clear
  end

  def history
    [{ role: "user", content: "Bach (123): hello" }]
  end

  def test_system_prompt_is_sent_first
    messages = build_messages(history, "Mochi")
    assert_equal "system", messages.first[:role]
    assert_equal "Bach (123): hello", messages.last[:content]
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
    assert_equal OPENAI_MAX_COMPLETION_TOKENS, sent[:max_completion_tokens]
    assert_equal OPENAI_REASONING_EFFORT, sent[:reasoning_effort]
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
    assert_equal OPENAI_FALLBACK_REASONING_EFFORT, client.requests.last[:reasoning_effort]
  end

  def test_empty_answer_is_logged_with_the_reason
    ask_ai(FakeClient.new(answers: ["", "ok"]), history, "Mochi")
    assert_includes LOGS.first, "finish_reason: length"
    assert_includes LOGS.first, "reasoning: 4000"
  end

  def test_retries_only_once
    client = FakeClient.new(answers: ["", ""])
    assert_equal "", ask_ai(client, history, "Mochi")
    assert_equal 2, client.requests.length
  end

  def test_api_error_returns_nil_and_does_not_retry
    client = FakeClient.new(error: Faraday::ServerError.new("boom"))
    assert_nil ask_ai(client, history, "Mochi")
    assert_equal 1, client.requests.length
  end
end
