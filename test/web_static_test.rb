require_relative "web_test_helper"

# The built React app (web/dist) is served by the same Sinatra app as the API.
class WebStaticTest < WebApiTest
  LOCALHOST = { "HTTP_HOST" => "localhost:4567" }.freeze

  def setup
    super
    FileUtils.rm_rf(Dir.glob(File.join(WEB_DIST_DIR, "*")))
    FileUtils.mkdir_p(File.join(WEB_DIST_DIR, "assets"))
    File.write(File.join(WEB_DIST_DIR, "index.html"), "<h1>app</h1>")
    File.write(File.join(WEB_DIST_DIR, "assets", "app.js"), "console.log(1)")
  end

  def test_serves_the_built_app_and_falls_back_to_index_for_pages
    get "/", {}, LOCALHOST
    assert_includes last_response.body, "<h1>app</h1>"
    assert_includes last_response.headers["content-type"], "text/html"
    get "/memory/people", {}, LOCALHOST # a page of the React app, not a file
    assert_includes last_response.body, "<h1>app</h1>"
    get "/assets/app.js", {}, LOCALHOST
    assert_equal "console.log(1)", last_response.body
  end

  def test_pages_need_no_token_but_still_need_the_right_host
    get "/", {}, LOCALHOST
    assert_equal 200, last_response.status
    get "/", {}, { "HTTP_HOST" => "evil.com" }
    assert_equal 403, last_response.status
  end

  def test_never_serves_files_outside_dist_and_keeps_api_404s_as_json
    File.write(File.join(File.dirname(WEB_DIST_DIR), ".env"), "DISCORD_BOT_TOKEN=secret")
    get "/..%2F.env", {}, LOCALHOST
    refute_includes last_response.body, "DISCORD_BOT_TOKEN"
    assert_nil web_static_file("/../.env")
    assert_nil web_static_file("/assets") # a folder is not a file
    api :get, "/api/nope"
    assert_equal 404, last_response.status
    assert json["error"]
  end

  def test_explains_how_to_build_when_dist_is_missing
    FileUtils.rm_f(File.join(WEB_DIST_DIR, "index.html"))
    get "/", {}, LOCALHOST
    assert_equal 200, last_response.status
    assert_includes last_response.body, "npm run build"
  end
end
