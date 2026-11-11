# Shared setup for the web API tests (test/web_*_test.rb). Not a test file itself.
# The API is called through rack-test: no server is started and no port is opened.
require_relative "test_helper"
require "json"
require "rack/test"
require_relative "../web_api/web_app"

TEST_TOKEN = "test-token-123"

# Pretend Discord objects, with only what the web API reads from them.
FakeWebChannel = Struct.new(:id, :name, :readable)
FakeWebProfile = Struct.new(:id, :username)
FakeWebServer = Struct.new(:id, :name, :icon_url, :text_channels, :bot)

# The bot's own member in a server. Real discordrb asks Discord's permission rules; here each channel just says.
FakeWebMember = Struct.new(:display_name) do
  def permission?(_action, channel) = channel.readable
end

class FakeWebBot
  attr_reader :servers, :profile

  def initialize(servers)
    @servers = servers.to_h { |server| [server.id, server] } # discordrb: { 111 => server }
    @profile = FakeWebProfile.new(1, "Cake")
  end
end

# One server (111, "Test Server") with a readable channel (900, general) and one Cake can't read (901, secret)
def fake_web_server
  channels = [FakeWebChannel.new(900, "general", true), FakeWebChannel.new(901, "secret", false)]
  FakeWebServer.new(111, "Test Server", nil, channels, FakeWebMember.new("Cake"))
end

class WebApiTest < Minitest::Test
  include Rack::Test::Methods

  def setup
    clear_test_memory
    LOGS.clear
    @context = WebContext.new(bot: FakeWebBot.new([fake_web_server]), client: FakeClient.new, histories: {},
                              ai_config_path: File.join(Dir.mktmpdir("cake-ai-config"), "ai_config.txt"),
                              token: TEST_TOKEN, port: 4567, started_at: Time.new(2026, 11, 11, 12, 0, 0))
  end

  def app
    @app ||= CakeWebApp.new_for(@context)
  end

  # Call the API like the web page does. body: a Hash is sent as JSON, a String is sent as it is.
  def api(method, path, body = nil, token: TEST_TOKEN, host: "localhost:4567")
    headers = { "HTTP_HOST" => host, "CONTENT_TYPE" => "application/json" }
    headers["HTTP_X_CAKE_TOKEN"] = token if token
    payload = body.is_a?(String) || body.nil? ? body : JSON.generate(body)
    custom_request(method.to_s.upcase, path, payload, headers)
  end

  def json
    JSON.parse(last_response.body)
  end

  # For work the API does on another thread: wait until the block is true, or fail after 2 seconds
  def wait_until
    200.times do
      return if yield

      sleep 0.01
    end
    flunk "waited 2 seconds for something that never happened"
  end
end
