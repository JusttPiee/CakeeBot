require_relative "test_helper"
require_relative "../config"
require_relative "../tool_list"

# Tool tests. No real web requests: only blocked links and fake data are used.
class ToolsTest < Minitest::Test
  def test_unknown_tool_gives_an_error_instead_of_crashing
    assert_includes run_tool("launch_rockets", "{}"), "no tool called launch_rockets"
  end

  def test_bad_json_arguments_give_an_error
    assert_includes run_tool("read_webpage", "{not json"), "not valid JSON"
  end

  def test_localhost_is_blocked
    assert_includes run_tool("read_webpage", '{"url":"http://localhost:3000"}'), "blocked"
  end

  def test_private_network_address_is_blocked
    assert_includes run_tool("read_webpage", '{"url":"http://192.168.1.1/admin"}'), "blocked"
  end

  def test_only_web_links_are_allowed
    assert_includes run_tool("read_webpage", '{"url":"file:///C:/Windows/win.ini"}'), "only http and https"
  end

  def test_html_becomes_plain_text
    html = "<html><style>p{}</style><script>alert(1)</script><p>Hello &amp; welcome</p></html>"
    assert_equal "Hello & welcome", html_to_text(html).strip
  end

  def test_search_results_are_numbered_with_links
    data = { "results" => [{ "title" => "Hanoi weather", "url" => "https://example.com", "content" => "28°C, sunny" }] }
    assert_equal "1. Hanoi weather\nhttps://example.com\n28°C, sunny", format_search_results(data)
  end

  def test_no_search_results
    assert_equal "No results found.", format_search_results({ "results" => [] })
  end
end
