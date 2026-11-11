require_relative "test_helper"
require_relative "../web_api/web_token"

class WebTokenTest < Minitest::Test
  def teardown
    ENV.delete("WEB_UI_TOKEN")
  end

  def test_creates_a_token_once_and_saves_it
    ENV.delete("WEB_UI_TOKEN")
    path = File.join(Dir.mktmpdir, ".env")
    File.write(path, "OPENAI_MODEL=\nWEB_UI_TOKEN=\n")
    token = load_or_create_web_token(path)
    assert_match(/\A[0-9a-f]{48}\z/, token)
    assert_includes File.read(path), "WEB_UI_TOKEN=#{token}\n"
    assert_equal 1, File.read(path).scan("WEB_UI_TOKEN=").length
    assert_equal token, load_or_create_web_token(path) # second call: same token
  end

  def test_adds_the_line_when_the_file_has_none
    ENV.delete("WEB_UI_TOKEN")
    path = File.join(Dir.mktmpdir, ".env")
    File.write(path, "OPENAI_MODEL=x") # no newline at the end
    token = load_or_create_web_token(path)
    assert_equal "OPENAI_MODEL=x\nWEB_UI_TOKEN=#{token}\n", File.read(path)
  end

  def test_uses_the_token_already_set
    ENV["WEB_UI_TOKEN"] = "mine"
    assert_equal "mine", load_or_create_web_token(File.join(Dir.mktmpdir, ".env"))
  end
end
