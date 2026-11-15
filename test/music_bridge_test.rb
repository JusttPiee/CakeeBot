require_relative "test_helper"
require "json"
require "timeout"
require_relative "../music_bridge"

# Plays the Node side with IO.pipe, so no real Node starts.
class FakeNode
  attr_reader :spawn_count

  def initialize(dies_at_once: false)
    @dies_at_once = dies_at_once
    @spawn_count = 0
  end

  def spawner
    lambda do
      @spawn_count += 1
      @stdin_read, stdin_write = IO.pipe
      stdout_read, @stdout_write = IO.pipe
      stderr_read, @stderr_write = IO.pipe
      @stdout_write.close if @dies_at_once
      [stdin_write, stdout_read, stderr_read, nil]
    end
  end

  def read_command_line = @stdin_read.gets
  def print_event(line) = @stdout_write.puts(line)
  def print_stderr(line) = @stderr_write.puts(line)
  def close_stdout = @stdout_write.close
end

class MusicBridgeTest < Minitest::Test
  def setup
    LOGS.clear
    @bridges = []
  end

  def teardown
    @bridges.each(&:stop)
  end

  def make_bridge(node, **options)
    bridge = MusicBridge.new(on_event: options.delete(:on_event) || ->(_) {}, spawner: node.spawner,
                             sleeper: ->(_) {}, **options)
    @bridges << bridge
    bridge
  end

  def within(seconds = 3, &block) = Timeout.timeout(seconds, &block)

  def wait_until(&condition)
    within { sleep 0.01 until condition.call }
  end

  def test_send_command_writes_one_json_line
    node = FakeNode.new
    bridge = make_bridge(node)
    bridge.start
    assert bridge.send_command("play", guild: 1, url: "u")
    assert_equal({ "op" => "play", "guild" => "1", "url" => "u" }, JSON.parse(within { node.read_command_line }))
  end

  def test_channel_id_is_written_as_string
    node = FakeNode.new
    bridge = make_bridge(node)
    bridge.start
    bridge.send_command("join", guild: 1, channel: 22)
    assert_equal "22", JSON.parse(within { node.read_command_line })["channel"]
  end

  def test_events_reach_on_event
    events = Queue.new
    node = FakeNode.new
    make_bridge(node, on_event: ->(e) { events << e }).start
    node.print_event('{"event":"finished","guild":"1"}')
    assert_equal({ "event" => "finished", "guild" => "1" }, within { events.pop })
  end

  def test_bad_json_is_logged_and_skipped
    events = Queue.new
    node = FakeNode.new
    make_bridge(node, on_event: ->(e) { events << e }).start
    node.print_event("not json")
    node.print_event('{"event":"ready"}')
    assert_equal "ready", within { events.pop }["event"]
    assert(LOGS.any? { |l| l.include?("🎵") && l.include?("not json") })
  end

  def test_stderr_lines_are_logged
    node = FakeNode.new
    make_bridge(node).start
    node.print_stderr("hello from node")
    wait_until { LOGS.include?("🎵 node: hello from node") }
  end

  def test_ready_after_ready_event_and_false_after_stop
    events = Queue.new
    node = FakeNode.new
    bridge = make_bridge(node, on_event: ->(e) { events << e }, delays: [])
    bridge.start
    refute bridge.ready?
    node.print_event('{"event":"ready"}')
    within { events.pop }
    assert bridge.ready?
    node.close_stdout
    within { events.pop }
    wait_until { !bridge.ready? }
  end

  def test_node_stopped_event_on_eof
    events = Queue.new
    node = FakeNode.new
    make_bridge(node, on_event: ->(e) { events << e }, delays: []).start
    node.close_stdout
    assert_equal "node_stopped", within { events.pop }["event"]
  end

  def test_restarts_then_gives_up
    node = FakeNode.new(dies_at_once: true)
    bridge = make_bridge(node, delays: [0, 0])
    bridge.start
    wait_until { LOGS.any? { |l| l.include?("Music stopped: Node keeps crashing") } }
    assert_equal 3, node.spawn_count
    refute bridge.running?
    refute bridge.send_command("stop", guild: "1")
  end

  def test_counter_resets_when_node_ran_longer_than_window
    node = FakeNode.new
    now = 0.0
    bridge = make_bridge(node, delays: [0], clock: -> { now })
    bridge.start
    now += MusicBridge::RESTART_WINDOW_SECONDS + 1
    node.close_stdout
    wait_until { node.spawn_count == 2 }
    now += MusicBridge::RESTART_WINDOW_SECONDS + 1
    node.close_stdout
    wait_until { node.spawn_count == 3 } # a second restart works because the counter was reset
  end

  def test_failed_spawn_after_long_run_still_gives_up
    node = FakeNode.new
    now = 0.0
    calls = 0
    spawner = lambda do
      calls += 1
      raise Errno::ENOENT, "node" if calls > 1
      node.spawner.call
    end
    bridge = MusicBridge.new(on_event: ->(_) {}, spawner: spawner, sleeper: ->(_) {}, delays: [0, 0], clock: -> { now })
    @bridges << bridge
    bridge.start
    now += MusicBridge::RESTART_WINDOW_SECONDS + 1
    node.close_stdout
    wait_until { LOGS.any? { |l| l.include?("Music stopped: Node keeps crashing") } }
    assert_equal 3, calls
  end

  def test_raising_on_event_does_not_stop_restart
    node = FakeNode.new
    bridge = make_bridge(node, on_event: ->(_) { raise "boom" }, delays: [0])
    bridge.start
    node.close_stdout
    wait_until { node.spawn_count == 2 }
    wait_until { LOGS.any? { |l| l.include?("node_stopped handler failed: boom") } }
  end

  def test_stop_does_not_restart
    node = FakeNode.new
    bridge = make_bridge(node, delays: [0, 0])
    bridge.start
    bridge.stop
    node.close_stdout # the real Node exits when its stdin closes
    wait_until { !bridge.running? }
    sleep 0.1
    assert_equal 1, node.spawn_count
  end

  def test_send_command_false_before_start
    refute make_bridge(FakeNode.new).send_command("stop", guild: "1")
  end

  def test_missing_parts_named
    missing = music_missing_parts(command_exists: ->(name) { name != "yt-dlp" }, folder: Dir.mktmpdir)
    assert_includes missing, "yt-dlp"
    assert(missing.any? { |m| m.start_with?("music/node_modules") })
    refute_includes missing, "node"
  end

  def test_nothing_missing_when_all_present
    folder = Dir.mktmpdir
    FileUtils.mkdir_p(File.join(folder, "node_modules"))
    assert_empty music_missing_parts(command_exists: ->(_) { true }, folder: folder)
  end

  def test_command_on_path_uses_pathext
    dir = Dir.mktmpdir
    File.write(File.join(dir, "node.exe"), "")
    File.chmod(0o755, File.join(dir, "node.exe"))
    assert command_on_path?("node", path: dir, pathext: ".COM;.EXE")
    refute command_on_path?("node", path: dir, pathext: "")
    refute command_on_path?("ffmpeg", path: dir, pathext: ".EXE")
  end

  def test_command_on_path_finds_exact_name
    dir = Dir.mktmpdir
    File.write(File.join(dir, "yt-dlp"), "")
    File.chmod(0o755, File.join(dir, "yt-dlp"))
    assert command_on_path?("yt-dlp", path: dir, pathext: "")
  end
end
