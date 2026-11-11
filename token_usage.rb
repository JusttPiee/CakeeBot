# How many tokens each OpenAI request used, printed as one line in the terminal (and the log files),
# so the user can see what each kind of request costs and keep the bill under control:
#
#   🪙 chat: in 3,214 (cached 2,048) · out 156 (thinking 64) · since start: in 41,870 · out 2,315
#
#   in       tokens sent to OpenAI (prompt, history, tool results)
#   cached   the part of "in" OpenAI had cached; it is billed much cheaper
#   out      tokens OpenAI wrote, thinking included; output is the expensive part
#   thinking the part of "out" spent on reasoning, never shown to anyone
# The "since start" totals count from when the bot started (they live in RAM).

TOKEN_TOTALS = { input: 0, output: 0 }
TOKEN_TOTALS_LOCK = Mutex.new

# label: what the request was for ("chat", "compaction", "tidy", "buildmemory", "embeddings").
# Never raises: counting tokens must not break a reply.
def log_token_usage(label, response)
  usage = token_usage_of(response)
  return if usage.nil?

  totals = add_to_token_totals(usage)
  log "🪙 #{label}: #{token_usage_text(usage)} · since start: in #{with_commas(totals[:input])} · out #{with_commas(totals[:output])}"
rescue StandardError
  nil
end

def token_totals
  TOKEN_TOTALS_LOCK.synchronize { TOKEN_TOTALS.dup }
end

def reset_token_totals
  TOKEN_TOTALS_LOCK.synchronize { TOKEN_TOTALS.merge!(input: 0, output: 0) }
end

# --- helpers ---

# { input:, cached:, output:, reasoning: } from a Responses API or an Embeddings API answer, or nil if it has none
def token_usage_of(response)
  usage = response.is_a?(Hash) ? response["usage"] : nil
  return nil unless usage.is_a?(Hash)

  { input: (usage["input_tokens"] || usage["prompt_tokens"]).to_i,
    cached: usage.dig("input_tokens_details", "cached_tokens").to_i,
    output: usage["output_tokens"].to_i,
    reasoning: usage.dig("output_tokens_details", "reasoning_tokens").to_i }
end

def add_to_token_totals(usage)
  TOKEN_TOTALS_LOCK.synchronize do
    TOKEN_TOTALS[:input] += usage[:input]
    TOKEN_TOTALS[:output] += usage[:output]
    TOKEN_TOTALS.dup
  end
end

# "in 3,214 (cached 2,048) · out 156 (thinking 64)". The parts in brackets only when they are not 0.
def token_usage_text(usage)
  input = "in #{with_commas(usage[:input])}"
  input += " (cached #{with_commas(usage[:cached])})" if usage[:cached].positive?
  output = "out #{with_commas(usage[:output])}"
  output += " (thinking #{with_commas(usage[:reasoning])})" if usage[:reasoning].positive?
  "#{input} · #{output}"
end

# 41870 => "41,870"
def with_commas(number)
  number.to_s.reverse.scan(/\d{1,3}/).join(",").reverse
end
