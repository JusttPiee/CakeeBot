require_relative "test_helper"
require_relative "../config"

class ConfigTest < Minitest::Test
  def teardown
    ENV.delete("CAKEE_TEST_SETTING")
  end

  def test_uses_value_from_env
    ENV["CAKEE_TEST_SETTING"] = "gpt-test"
    assert_equal "gpt-test", setting("CAKEE_TEST_SETTING", default: "gpt-6-luna")
  end

  def test_uses_default_when_missing
    assert_equal "gpt-6-luna", setting("CAKEE_TEST_SETTING", default: "gpt-6-luna")
  end

  def test_uses_default_when_empty
    ENV["CAKEE_TEST_SETTING"] = "   " # e.g. "OPENAI_MODEL=" left empty in .env
    assert_equal "gpt-6-luna", setting("CAKEE_TEST_SETTING", default: "gpt-6-luna")
  end

  def test_trims_spaces
    ENV["CAKEE_TEST_SETTING"] = "  gpt-test  "
    assert_equal "gpt-test", setting("CAKEE_TEST_SETTING", default: "gpt-6-luna")
  end

  def test_agreed_defaults
    assert_equal "low", OPENAI_REASONING_EFFORT
    assert_equal "none", OPENAI_FALLBACK_REASONING_EFFORT
    assert_equal 4000, OPENAI_MAX_OUTPUT_TOKENS
  end
end
