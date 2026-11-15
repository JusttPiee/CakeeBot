# The bridge between Ruby and the music process (music/index.js, Node).
# Ruby writes one JSON command per line to Node's stdin; Node answers with one JSON event per line on stdout.
# If Node dies, the bridge starts it again after a short wait (MUSIC_NODE_RESTART_DELAYS),
# and gives up when it keeps crashing within 5 minutes.
require 'json'
require 'open3'
require_relative './config'

MUSIC_FOLDER = File.join(__dir__, 'music')
MUSIC_NODE_SPAWNER = lambda do
  environment = { 'DISCORD_BOT_TOKEN' => ENV['DISCORD_BOT_TOKEN'] }
  Open3.popen3(environment, 'node', 'index.js', chdir: MUSIC_FOLDER)
end

# --- checking what is installed ---

# Is a program with this name somewhere on PATH? Works on Windows (PATHEXT: node.exe) and Linux.
def command_on_path?(name, path: ENV['PATH'], pathext: ENV['PATHEXT'])
  folders = path.to_s.split(File::PATH_SEPARATOR).reject(&:empty?)
  file_names = command_file_names(name, pathext)
  folders.any? do |folder|
    file_names.any? { |file_name| File.file?(File.join(folder, file_name)) }
  end
end

# "node" and ".COM;.EXE" => ["node", "node.com", "node.exe"]
def command_file_names(name, pathext)
  extensions = pathext.to_s.split(';').reject(&:empty?).map(&:downcase)
  [name] + extensions.map { |extension| name + extension }
end

# Names of the things music needs but this machine does not have. Empty means all is there.
def music_missing_parts(command_exists: method(:command_on_path?), folder: MUSIC_FOLDER)
  missing = %w[node yt-dlp ffmpeg].reject { |name| command_exists.call(name) }
  missing << 'music/node_modules (run npm install in music/)' unless Dir.exist?(File.join(folder, 'node_modules'))
  missing
end

# --- the bridge ---

class MusicBridge
  RESTART_WINDOW_SECONDS = 5 * 60 # a Node that ran longer than this before dying starts the restart count again

  def initialize(on_event:, spawner: MUSIC_NODE_SPAWNER, sleeper: Kernel.method(:sleep),
                 delays: MUSIC_NODE_RESTART_DELAYS, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
    @on_event = on_event
    @spawner = spawner
    @sleeper = sleeper
    @delays = delays
    @clock = clock
    @write_lock = Mutex.new
    @stdin = nil
    @running = false
    @ready = false
    @stopping = false
    @restarts = 0
  end

  # Starts Node. Returns true when it started.
  def start
    @stopping = false
    spawn_node
  end

  def running? = @running

  # True from Node's "ready" event until Node stops.
  def ready? = @ready

  # Sends one command line to Node. Returns false (and does not raise) when that is not possible.
  def send_command(op, guild:, **fields)
    fields = fields.transform_values { |value| id_field?(value) ? value.to_s : value }
    line = JSON.generate({ 'op' => op, 'guild' => guild.to_s }.merge(fields.transform_keys(&:to_s)))
    write_line(line)
  end

  # Closes Node's stdin, which makes Node exit. No restart afterwards.
  def stop
    @stopping = true
    @write_lock.synchronize { @stdin&.close }
  rescue IOError, SystemCallError
    nil
  end

  private

  # channel ids are sent as strings too, like guild ids
  def id_field?(value) = value.is_a?(Integer)

  def write_line(line)
    @write_lock.synchronize do
      return false unless @running

      @stdin.puts(line)
      @stdin.flush
      true
    end
  rescue IOError, SystemCallError => e
    log "🎵 Could not write to Node: #{e.message}"
    false
  end

  def spawn_node
    @started_at = @clock.call # set before spawning, so a failed spawn never looks like a long run
    @stdin, stdout, stderr, @wait_thread = @spawner.call
    @running = true
    @ready = false
    Thread.new { read_events(stdout) }
    Thread.new { read_stderr(stderr) }
    true
  rescue StandardError => e
    log "🎵 Could not start Node: #{e.message}"
    @running = false
    false
  end

  # Reads event lines until Node closes stdout, then decides about a restart.
  def read_events(stdout)
    begin
      stdout.each_line { |line| handle_line(line) }
    rescue StandardError => e
      log "🎵 Music reader failed: #{e.message}"
    end
    node_ended
  end

  def handle_line(line)
    event = JSON.parse(line)
    @ready = true if event['event'] == 'ready'
    @on_event.call(event)
  rescue JSON::ParserError
    log "🎵 Node sent something that is not JSON: #{line.strip}"
  rescue StandardError => e
    log "🎵 Music event failed: #{e.message}"
  end

  def read_stderr(stderr)
    stderr.each_line { |line| log "🎵 node: #{line.chomp}" }
  rescue StandardError => e
    log "🎵 Music stderr reader failed: #{e.message}"
  end

  def node_ended
    @running = false
    @ready = false
    return if @stopping

    log '🎵 Node stopped'
    tell_node_stopped
    restart_after_wait
  end

  # A failing handler must not stop the restart.
  def tell_node_stopped
    @on_event.call({ 'event' => 'node_stopped' })
  rescue StandardError => e
    log "🎵 node_stopped handler failed: #{e.message}"
  end

  def restart_after_wait
    @restarts = 0 if @clock.call - @started_at > RESTART_WINDOW_SECONDS
    delay = @delays[@restarts]
    if delay.nil?
      log '🎵 Music stopped: Node keeps crashing'
      return
    end
    @restarts += 1
    @sleeper.call(delay)
    spawn_node_unless_stopping
  end

  def spawn_node_unless_stopping
    return if @stopping

    # a failed start counts like a crash, so we do not retry forever
    node_ended unless spawn_node
  end
end
