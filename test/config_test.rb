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
  def test_saved_setting_uses_the_saved_value
    assert_equal 60, saved_setting("X_TEST", 45, { "X_TEST" => 60 })
  end

  def test_saved_setting_ignores_a_value_of_the_wrong_type
    assert_equal 45, saved_setting("X_TEST", 45, { "X_TEST" => "abc" })
    assert_equal "low", saved_setting("Y_TEST", "low", { "Y_TEST" => 3 })
  end

  def test_saved_setting_remembers_the_default
    saved_setting("Z_TEST", 7, {})
    assert_equal 7, CONFIG_DEFAULTS["Z_TEST"]
  end

  def test_broken_settings_file_gives_no_settings
    path = File.join(Dir.mktmpdir, "settings.json")
    assert_equal({}, read_saved_settings(path))            # missing
    File.write(path, "{ not json")
    assert_equal({}, read_saved_settings(path))            # broken
    File.write(path, "[1, 2]")
    assert_equal({}, read_saved_settings(path))            # not an object
  end
end
