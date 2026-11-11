require_relative "web_test_helper"
require_relative "../web_api/web_server"

class WebServerTest < Minitest::Test
  def teardown
    ENV.delete("WEB_UI_PORT")
    ENV.delete("WEB_UI")
  end

  def test_port_comes_from_env_when_it_is_a_usable_port
    assert_equal 4567, web_ui_port
    ENV["WEB_UI_PORT"] = "5000"
    assert_equal 5000, web_ui_port
    ENV["WEB_UI_PORT"] = "80" # needs admin rights on most systems
    assert_equal 4567, web_ui_port
    ENV["WEB_UI_PORT"] = "abc"
    assert_equal 4567, web_ui_port
  end

  def test_can_be_switched_off
    assert_equal true, web_ui_enabled?
    ENV["WEB_UI"] = "OFF"
    assert_equal false, web_ui_enabled?
  end

  def test_serves_on_localhost_and_a_busy_port_does_not_raise
    app = ->(_env) { [200, { "content-type" => "text/plain" }, ["hi"]] }
    server = run_web_server(app, 45_672)
    assert_equal "hi", Net::HTTP.get(URI("http://127.0.0.1:45672/"))
    LOGS.clear
    assert_nil start_web_server_safely(app, 45_672) # the port is taken by the server above
    assert(LOGS.any? { |line| line.include?("Web UI could not start (Errno::EADDRINUSE)") })
  ensure
    server&.stop(true)
  end
end
