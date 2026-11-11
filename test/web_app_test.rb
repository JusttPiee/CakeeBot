require_relative "web_test_helper"

class WebAppTest < WebApiTest
  def test_status_lists_the_bots_servers
    api :get, "/api/status"
    assert_equal 200, last_response.status
    assert_equal [{ "id" => "111", "name" => "Test Server", "icon_url" => nil }], json["servers"]
    assert_equal "Cake", json["bot_name"]
    assert_equal false, json["restart_needed"]
  end

  def test_wrong_or_missing_token_is_refused
    api :get, "/api/status", token: "wrong"
    assert_equal 401, last_response.status
    api :get, "/api/status", token: nil
    assert_equal 401, last_response.status
  end

  def test_another_host_is_refused # DNS rebinding: evil.com resolving to 127.0.0.1
    api :get, "/api/status", host: "evil.com"
    assert_equal 403, last_response.status
    api :get, "/api/status", host: "127.0.0.1:4567"
    assert_equal 200, last_response.status
  end

  def test_unknown_or_odd_server_ids_are_not_found
    ["999", "abc", "..%2F111"].each do |id|
      api :get, "/api/servers/#{id}/users"
      assert_equal 404, last_response.status, id
    end
  end

  def test_a_crash_in_a_route_is_a_json_500_and_is_logged
    @context.bot = nil # status will raise
    api :get, "/api/status"
    assert_equal 500, last_response.status
    assert json["error"]
    assert(LOGS.any? { |line| line.include?("Web UI request failed") })
  end
end
