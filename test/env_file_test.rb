require_relative "test_helper"
require_relative "../env_file"

class EnvFileTest < Minitest::Test
  def test_template_is_only_copied_outside_a_container
    Dir.mktmpdir do |dir|
      env, template = File.join(dir, ".env"), File.join(dir, ".env.example")
      File.write(template, "A=")
      assert create_env_from_template?(env, template, false)
      refute create_env_from_template?(env, template, true)
      File.write(env, "A=1")
      refute create_env_from_template?(env, template, false)
    end
  end

  def test_blank_variables_do_not_hide_saved_values
    env = { "WEB_UI_TOKEN" => "", "OPENAI_API_KEY" => "x", "OTHER" => "" }
    drop_blank_variables(%w[WEB_UI_TOKEN OPENAI_API_KEY], env)
    assert_equal({ "OPENAI_API_KEY" => "x", "OTHER" => "" }, env)
  end

  def test_error_messages_name_the_file_people_must_edit
    assert_equal "C:/bot/.env", settings_place("C:/bot/.env", false)
    assert_equal "the .env file next to compose.yaml (then run: docker compose up -d)", settings_place("/data/.env", true)
  end
end
