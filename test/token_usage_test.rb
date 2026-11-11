require_relative "test_helper"
require_relative "../token_usage"

# One line per OpenAI request, so the user can see what each kind of request costs.
class TokenUsageTest < Minitest::Test
  def setup
    LOGS.clear
    reset_token_totals
  end

  def chat_response(input:, cached:, output:, reasoning:)
    { "usage" => { "input_tokens" => input, "input_tokens_details" => { "cached_tokens" => cached },
                   "output_tokens" => output, "output_tokens_details" => { "reasoning_tokens" => reasoning } } }
  end

  def test_logs_input_output_cached_and_reasoning_tokens
    log_token_usage("chat", chat_response(input: 3214, cached: 2048, output: 156, reasoning: 64))
    assert_equal ["🪙 chat: in 3,214 (cached 2,048) · out 156 (thinking 64) · since start: in 3,214 · out 156"], LOGS
  end

  def test_the_totals_add_up_across_requests
    log_token_usage("chat", chat_response(input: 1000, cached: 0, output: 100, reasoning: 0))
    log_token_usage("compaction", chat_response(input: 2500, cached: 0, output: 400, reasoning: 0))
    assert_equal "🪙 compaction: in 2,500 · out 400 · since start: in 3,500 · out 500", LOGS.last
    assert_equal({ input: 3500, output: 500 }, token_totals)
  end

  def test_embeddings_only_have_input_tokens
    log_token_usage("embeddings", { "usage" => { "prompt_tokens" => 812, "total_tokens" => 812 } })
    assert_equal "🪙 embeddings: in 812 · out 0 · since start: in 812 · out 0", LOGS.last
  end

  def test_an_answer_without_usage_logs_nothing
    log_token_usage("chat", { "output" => [] })
    log_token_usage("chat", nil)
    assert_empty LOGS
  end

  def test_a_broken_usage_never_raises
    log_token_usage("chat", { "usage" => "weird" })
    assert_empty LOGS
  end
end
