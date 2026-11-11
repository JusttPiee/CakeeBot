require_relative "web_test_helper"

class WebConfigTest < WebApiTest
  def setup
    super
    FileUtils.rm_f(SETTINGS_FILE)
  end

  def teardown
    FileUtils.rm_f(SETTINGS_FILE) # other tests must not see a "restart needed"
  end

  def test_every_field_has_a_default_from_config_rb
    names = CONFIG_GROUPS.flat_map { |group| group[:fields].map { |field| field[:name] } }
    assert_equal 31, names.length
    assert_empty names - CONFIG_DEFAULTS.keys
    assert_equal names.uniq, names
  end

  def test_every_default_is_a_valid_value
    assert_empty config_errors(CONFIG_DEFAULTS.slice(*config_field_names))
  end

  def test_shows_fields_with_default_saved_and_running_values
    api :get, "/api/config"
    field = json["groups"].flat_map { |group| group["fields"] }.find { |f| f["name"] == "MAX_HISTORY_MESSAGES" }
    assert_equal({ "name" => "MAX_HISTORY_MESSAGES", "type" => "integer", "min" => 10, "max" => 200, "options" => nil,
                   "default" => 45, "saved" => nil, "running" => 45 }, field)
    assert_equal %w[chat history tools search buildmemory clear recent], json["groups"].map { |group| group["id"] }
    assert_equal ["OPENAI_MODEL", "OPENAI_TEMPERATURE"], json["read_only"].map { |f| f["name"] }
    assert_equal false, json["restart_needed"]
  end

  def test_saving_writes_only_what_differs_and_asks_for_a_restart
    api :put, "/api/config", { values: { "MAX_HISTORY_MESSAGES" => 60, "BUILD_MEMORY_MAX_PEOPLE" => 50 } }
    assert_equal 200, last_response.status
    assert_equal({ "MAX_HISTORY_MESSAGES" => 60 }, JSON.parse(File.read(SETTINGS_FILE)))
    assert_equal true, json["restart_needed"]
    api :get, "/api/status"
    assert_equal true, json["restart_needed"]
    api :put, "/api/config", { values: { "MAX_HISTORY_MESSAGES" => 45 } } # back to the default
    assert_equal({}, JSON.parse(File.read(SETTINGS_FILE)))
    assert_equal false, json["restart_needed"]
  end

  def test_a_second_save_keeps_what_the_first_one_saved
    api :put, "/api/config", { values: { "MAX_HISTORY_MESSAGES" => 60 } }
    api :put, "/api/config", { values: { "OPENAI_REASONING_EFFORT" => "high" } }
    assert_equal({ "MAX_HISTORY_MESSAGES" => 60, "OPENAI_REASONING_EFFORT" => "high" }, JSON.parse(File.read(SETTINGS_FILE)))
  end

  def test_bad_values_are_refused_and_nothing_is_written
    [{ "MAX_HISTORY_MESSAGES" => 5 }, { "MAX_HISTORY_MESSAGES" => "60" }, { "MAX_HISTORY_MESSAGES" => 60.5 },
     { "OPENAI_REASONING_EFFORT" => "extreme" }, { "DISCORD_BOT_TOKEN" => "x" }, { "MEMORY_DIR" => "C:/" }].each do |values|
      api :put, "/api/config", { values: values }
      assert_equal 422, last_response.status, values.inspect
      assert_equal values.keys, json["errors"].keys
    end
    api :put, "/api/config", { values: "everything" }
    assert_equal 422, last_response.status
    refute File.exist?(SETTINGS_FILE)
  end

  def test_the_low_mark_must_stay_below_the_high_mark
    api :put, "/api/config", { values: { "MAX_HISTORY_MESSAGES" => 15 } } # COMPACT_TARGET_MESSAGES is 20
    assert_equal 422, last_response.status
    assert_equal ["MAX_HISTORY_MESSAGES"], json["errors"].keys
    api :put, "/api/config", { values: { "MAX_HISTORY_TOKENS" => 8000 } } # HARD_MAX_HISTORY_TOKENS is 7500
    assert_equal ["MAX_HISTORY_TOKENS"], json["errors"].keys
    api :put, "/api/config", { values: { "MAX_HISTORY_TOKENS" => 8000, "HARD_MAX_HISTORY_TOKENS" => 12_000 } }
    assert_equal 200, last_response.status
  end

  def test_a_hand_edited_settings_file_with_odd_values_is_shown_as_not_saved
    File.write(SETTINGS_FILE, JSON.generate({ "MAX_HISTORY_MESSAGES" => "abc", "MEMORY_DIR" => "C:/", "MAX_TOOL_ROUNDS" => 9 }))
    api :get, "/api/config"
    fields = json["groups"].flat_map { |group| group["fields"] }.to_h { |field| [field["name"], field["saved"]] }
    assert_nil fields["MAX_HISTORY_MESSAGES"]
    assert_equal 9, fields["MAX_TOOL_ROUNDS"]
  end

  def test_no_secret_is_ever_in_the_answer
    ENV["OPENAI_API_KEY"] = "sk-secret-test"
    api :get, "/api/config"
    refute_includes last_response.body, "sk-secret-test"
  ensure
    ENV.delete("OPENAI_API_KEY")
  end
end
