require_relative "web_test_helper"

class WebChannelsTest < WebApiTest
  def setup
    super
    @context.history_loader = ->(_bot, _channel) { [:loaded] } # no Discord in tests
  end

  def test_lists_channels_with_their_ai_state
    add_ai_channel(@context.ai_config_path, "900")
    api :get, "/api/servers/111/channels"
    assert_equal [{ "id" => "900", "name" => "general", "ai_on" => true, "readable" => true },
                  { "id" => "901", "name" => "secret", "ai_on" => false, "readable" => false }], json
  end

  def test_turns_ai_on_and_off_without_restart
    api :put, "/api/servers/111/channels/900/ai", { on: true }
    assert_equal({ "id" => "900", "ai_on" => true }, json)
    assert_equal [:loaded], @context.histories[900]
    assert_equal ["900"], load_ai_channels(@context.ai_config_path)
    api :put, "/api/servers/111/channels/900/ai", { on: false }
    assert_equal({ "id" => "900", "ai_on" => false }, json)
    refute @context.histories.key?(900)
    assert_equal 2, LOGS.count { |line| line.include?("Test Server #general (web UI)") }
  end

  def test_refuses_unknown_and_unreadable_channels
    api :put, "/api/servers/111/channels/555/ai", { on: true }
    assert_equal 404, last_response.status
    api :put, "/api/servers/111/channels/901/ai", { on: true }
    assert_equal 422, last_response.status
    api :put, "/api/servers/111/channels/900/ai", { on: "yes" }
    assert_equal 422, last_response.status
    assert_empty load_ai_channels(@context.ai_config_path)
  end

  def test_a_channel_whose_history_cannot_be_loaded_stays_off
    @context.history_loader = ->(_bot, _channel) { raise "Discord is down" }
    api :put, "/api/servers/111/channels/900/ai", { on: true }
    assert_equal 500, last_response.status
    assert_empty load_ai_channels(@context.ai_config_path)
    refute @context.histories.key?(900)
  end
end
