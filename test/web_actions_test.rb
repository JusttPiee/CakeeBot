require_relative "web_test_helper"

class WebActionsTest < WebApiTest
  def setup
    super
    BUILD_MEMORY_RUNNING.clear
    WEB_BUILD_REPORTS.clear
  end

  def test_restart_answers_first_then_restarts_once
    calls = Queue.new
    @context.restarter = -> { calls << :restart }
    api :post, "/api/restart"
    assert_equal 202, last_response.status
    api :post, "/api/restart" # Review Focus 5: a double click
    assert_equal 409, last_response.status
    assert_equal :restart, calls.pop # waits for the thread
    assert_empty calls
    assert(LOGS.any? { |line| line.include?("Restart requested from the web UI") })
  end

  def test_build_memory_runs_once_and_keeps_its_report
    gate = Queue.new
    @context.build_channels = lambda do |_server|
      gate.pop # the build waits here until the test lets it go
      []
    end
    api :get, "/api/servers/111/buildmemory"
    assert_equal({ "running" => false, "last_report" => nil, "finished_at" => nil }, json)
    api :post, "/api/servers/111/buildmemory"
    assert_equal 202, last_response.status
    api :get, "/api/servers/111/buildmemory"
    assert_equal true, json["running"]
    api :post, "/api/servers/111/buildmemory" # Review Focus 5
    assert_equal 409, last_response.status
    gate << :go
    wait_until { !memory_build_running?("111") }
    api :get, "/api/servers/111/buildmemory"
    assert_equal false, json["running"]
    assert_includes json["last_report"], "Read 0 messages in 0 channels"
    assert json["finished_at"]
    assert(LOGS.any? { |line| line.include?("!buildmemory started from the web UI in Test Server") })
  end

  def test_a_build_that_cannot_even_start_reading_still_finishes_with_a_report
    @context.build_channels = ->(_server) { raise "Discord is down" }
    api :post, "/api/servers/111/buildmemory"
    wait_until { !memory_build_running?("111") }
    api :get, "/api/servers/111/buildmemory"
    assert_includes json["last_report"], "Building memory failed"
  end
end
