# Shared setup for all tests. Load it at the top of every test file.
require "minitest/autorun"
require "tmpdir"
require "fileutils"

# Memory files go to a temp folder in tests, never to the real memory/ folder.
# This must run before config.rb is loaded (config.rb reads it into MEMORY_DIR).
ENV["CAKE_TEST_MEMORY_DIR"] ||= Dir.mktmpdir("cake-memory")

# log and describe_openai_error normally come from cakee.rb.
# In tests, log lines are collected in LOGS so tests can check them.
LOGS = []
def log(message) = LOGS << message
def describe_openai_error(_error) = "fake error"

# Start a test with no memory files at all
def clear_test_memory
  FileUtils.rm_rf(Dir.glob(File.join(ENV["CAKE_TEST_MEMORY_DIR"], "*")))
end

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
