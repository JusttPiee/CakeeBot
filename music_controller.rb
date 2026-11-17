# The music controller: one player per server.
# Commands (!play, buttons...) come from discordrb threads, events come from the bridge's reader
# thread (Node), plus the YouTube-search threads and the idle timer. One Mutex (@lock) guards all
# server state. Commands to Node are sent while holding it, so they reach Node in the right order.
# Discord work (panel, short notes) and the YouTube search are never done while holding it:
# the code under the lock collects them in `later`, and they run after the lock is released.
#
# How a song ends (and why skip is safe):
#   Once "play" is sent, Node sends exactly one "finished" or "failed" for that song
#   (music/player.js: the song ends once; a stop on a song that already ended sends nothing,
#   because that song's own finished/failed is already on its way).
#   - Skip of a song Node has (song_sent): send "stop" and wait for that one event. `skipping`
#     stops a second skip from sending another stop before it arrives.
#   - Skip of a song Node does not have yet (its YouTube search is still running): no event will
#     ever come, so we move on here at once. The song number goes up, so the late search result
#     is thrown away.
#   - A finished/failed while song_sent is false is left over (after a stop or a reset): ignored.
require_relative './config'
require_relative './music_queue'
require_relative './music_sources'
require_relative './music_panel'
require_relative './music_server_state'
require_relative './music_controller_panel' # panel and notes (Discord calls)

# Runs the block after `seconds`, in its own thread. Tests pass their own scheduler
MUSIC_SCHEDULER = lambda do |seconds, &block|
  Thread.new do
    sleep seconds
    block.call
  end
end

# Node's reason when joining a voice channel fails (JOIN_FAILED_REASON in music/reasons.js)
MUSIC_JOIN_FAILURE = 'could not join the voice channel'

# Posted once when MUSIC_MAX_FAILURES_IN_A_ROW songs failed one after another
MUSIC_TOO_MANY_FAILURES_TEXT = "❗ #{MUSIC_MAX_FAILURES_IN_A_ROW} songs in a row failed, so I stopped. " \
                               'yt-dlp may need an update (`yt-dlp -U`).'

class MusicController
  def initialize(bridge:, poster:, resolver: method(:resolve_search_track), scheduler: MUSIC_SCHEDULER)
    @bridge = bridge
    @poster = poster
    @resolver = resolver
    @scheduler = scheduler
    @lock = Mutex.new
    @servers = {}
    @panel_locks = {}
  end

  # --- questions ---

  # Is the music process (Node) up and logged in?
  def available?
    safely('available?', false) { @bridge.ready? }
  end

  # The voice channel Cake is in for this server, or nil
  def voice_channel_id(guild_id)
    with_lock('voice_channel_id') { @servers[guild_id]&.voice_channel_id }
  end

  # Is a song current (playing or paused)?
  def busy?(guild_id)
    with_lock('busy?', false) { !@servers[guild_id]&.queue&.current.nil? }
  end

  # [the current song or nil, the waiting songs]
  def queue_snapshot(guild_id)
    with_lock('queue_snapshot', [nil, []]) do
      queue = @servers[guild_id]&.queue
      queue ? [queue.current, queue.waiting] : [nil, []]
    end
  end

  # --- commands ---

  # Adds songs; joins voice and starts playing when nothing is current.
  # Returns :started, :queued or :moved_and_started
  def play(guild_id, voice_channel_id, text_channel, tracks)
    with_lock('play') do |later|
      state = (@servers[guild_id] ||= MusicServerState.fresh)
      play_locked(state, guild_id, voice_channel_id, text_channel, tracks, later)
    end
  end

  # Pause when playing, resume when paused. Returns :paused, :resumed or nil (nothing playing)
  def toggle_pause(guild_id)
    with_lock('toggle_pause') do |later|
      state = @servers[guild_id]
      paused = state && !state.queue.paused
      next nil unless state && change_pause(state, guild_id, paused, later)

      paused ? :paused : :resumed
    end
  end

  # For !pause and !resume. false when nothing is playing or it is already like that
  def set_paused(guild_id, paused)
    with_lock('set_paused', false) do |later|
      state = @servers[guild_id]
      state ? change_pause(state, guild_id, paused, later) : false
    end
  end

  # The server's volume (0-100), or nil when Cake is not in voice there
  def volume(guild_id)
    with_lock('volume') do |_later|
      state = @servers[guild_id]
      state&.voice_channel_id ? state.volume : nil
    end
  end

  # !volume 30: sets an exact level. Returns the new level, or nil when Cake is not in voice
  def set_volume(guild_id, level)
    with_lock('set_volume') do |later|
      volume_locked(@servers[guild_id], guild_id, level, later)
    end
  end

  # The 🔉 / 🔊 buttons: moves the level by `step` (e.g. -10). Returns the new level, or nil when not in voice
  def change_volume(guild_id, step)
    with_lock('change_volume') do |later|
      state = @servers[guild_id]
      volume_locked(state, guild_id, state.volume + step, later) if state
    end
  end

  # Skips the current song. false when there is nothing to skip (or a skip is already on its way)
  def skip(guild_id)
    with_lock('skip', false) do |later|
      state = @servers[guild_id]
      state ? skip_locked(state, guild_id, later) : false
    end
  end

  # Drops the waiting songs of the current song's playlist, then skips the current song.
  # Returns how many waiting songs were dropped
  def skip_playlist(guild_id)
    with_lock('skip_playlist', 0) do |later|
      state = @servers[guild_id]
      next 0 if state.nil? || state.queue.current.nil?

      removed = state.queue.skip_playlist!
      skip_locked(state, guild_id, later)
      removed
    end
  end

  # Removes all waiting songs; the current one keeps playing. Returns how many were removed
  def clear_queue(guild_id)
    with_lock('clear_queue', 0) do |later|
      state = @servers[guild_id]
      next 0 if state.nil?

      later << -> { refresh_panel(guild_id) }
      state.queue.clear!
    end
  end

  # The loop mode (:off, :song or :queue), :off when no music has started here
  def loop_mode(guild_id)
    with_lock('loop_mode', :off) { @servers[guild_id]&.queue&.loop_mode || :off }
  end

  # !loop and the Loop button: off -> song -> queue -> off. Returns the new mode, or nil when nothing is playing
  def cycle_loop(guild_id)
    with_lock('cycle_loop') do |later|
      loop_locked(@servers[guild_id], guild_id, later) { |queue| queue.cycle_loop! }
    end
  end

  # !loop song (or off, queue): sets one mode. Returns it, or nil when nothing is playing
  def set_loop(guild_id, mode)
    with_lock('set_loop') do |later|
      loop_locked(@servers[guild_id], guild_id, later) { |queue| queue.loop_mode = mode }
    end
  end

  # Mixes the waiting songs into a random order. Returns how many were mixed (0 = nothing to mix).
  # The panel only shows how many songs wait, so it does not change
  def shuffle(guild_id)
    with_lock('shuffle', 0) do
      state = @servers[guild_id]
      state ? state.queue.shuffle! : 0
    end
  end

  # Stops the music, empties the queue, leaves voice and marks the panel stopped
  def stop(guild_id)
    with_lock('stop') do |later|
      state = @servers[guild_id]
      next if state.nil? || !state.active?

      stop_locked(state, guild_id, later)
    end
  end

  # Someone joined or left Cake's voice channel. Nobody else left: stop
  def listeners_changed(guild_id, other_humans_count)
    safely('listeners_changed') { stop(guild_id) if other_humans_count.zero? }
  end

  # --- events from Node ---

  # One event Hash from the bridge, like { "event" => "finished", "guild" => "123" }
  def handle_event(event)
    safely('handle_event') do
      name = event['event']
      next reset_every_server if name == 'node_stopped'

      guild_id = Integer(event['guild'].to_s, exception: false) # Node sends ids as strings
      with_lock("event #{name}") do |later|
        state = @servers[guild_id]
        event_locked(state, guild_id, name, event['reason'].to_s, later) if state
      end
    end
  end

  private

  # --- play ---

  def play_locked(state, guild_id, channel_id, text_channel, tracks, later)
    state.idle_token = nil # a new song cancels the idle wait
    moved = join_if_needed(state, guild_id, channel_id)
    state.text_channel = text_channel if state.queue.current.nil?
    state.queue.add(tracks)
    if state.queue.current
      later << -> { refresh_panel(guild_id) } # the panel shows how many songs wait
      return :queued
    end
    move_on(state, guild_id, later)
    moved ? :moved_and_started : :started
  end

  # Sends "join" when Cake is not in voice, or is idle in another channel.
  # Returns true when Cake moves from another channel
  def join_if_needed(state, guild_id, channel_id)
    return false if state.voice_channel_id == channel_id
    return false if state.voice_channel_id && state.queue.current # busy there; !play checks this first

    moved = !state.voice_channel_id.nil?
    @bridge.send_command('join', guild: guild_id, channel: channel_id)
    state.voice_channel_id = channel_id
    state.joined = false
    moved
  end

  # The next song becomes current and starts, or the idle wait starts when none waits.
  # `why` (:finished, :skipped or :failed) is why the current song ends; the loop mode uses it (MusicQueue#advance!)
  def move_on(state, guild_id, later, why = :failed)
    state.queue.advance!(why)
    begin_song(state, guild_id, later)
  end

  # Starts the current song: sends "play", or first searches YouTube when it has no url (Spotify)
  def begin_song(state, guild_id, later)
    track = state.queue.current
    return start_idle_wait(state, guild_id, later) if track.nil?

    state.song_number += 1
    state.song_sent = false
    state.skipping = false
    state.queue.paused = false # a new song in Node always starts unpaused
    if track.url.nil?
      number = state.song_number
      later << -> { search_in_background(guild_id, number, track) }
    else
      send_play(state, guild_id, track)
    end
    later << -> { refresh_panel(guild_id) }
  end

  def send_play(state, guild_id, track)
    state.song_sent = @bridge.send_command('play', guild: guild_id, url: track.url, volume: state.volume)
  end

  # --- loop ---

  # Changes the loop mode with the block and refreshes the panel. nil when no song is current
  def loop_locked(state, guild_id, later)
    return nil if state.nil? || state.queue.current.nil?

    yield state.queue
    later << -> { refresh_panel(guild_id) }
    state.queue.loop_mode
  end

  # --- volume ---

  # Sets the server's volume (kept between 0 and 100), tells Node at once and refreshes the panel.
  # Returns the new level, or nil when Cake is not in voice
  def volume_locked(state, guild_id, level, later)
    return nil unless state&.voice_channel_id

    state.volume = level.to_i.clamp(0, 100)
    @bridge.send_command('volume', guild: guild_id, volume: state.volume)
    later << -> { refresh_panel(guild_id) }
    state.volume
  end

  # --- songs without a url (Spotify): search YouTube when their turn comes ---

  def search_in_background(guild_id, number, track)
    Thread.new do
      found = search_youtube(track)
      with_lock('search result') { |later| search_done(guild_id, number, found, later) }
    end
  end

  def search_youtube(track)
    @resolver.call(track)
  rescue StandardError => e
    log "🎵 YouTube search failed: #{e.message}"
    nil
  end

  # Plays what the search found, or posts a note and moves on.
  # Does nothing when the song was skipped or the music stopped meanwhile
  def search_done(guild_id, number, found, later)
    state = @servers[guild_id]
    return if state.nil? || state.song_number != number

    track = state.queue.current
    return song_failed(state, guild_id, "❗ Couldn't find \"#{track.search}\" on YouTube, skipping.", later) if found.nil?

    track.url = found.url
    track.duration = found.duration
    track.thumbnail = found.thumbnail
    send_play(state, guild_id, track)
    later << -> { refresh_panel(guild_id) }
  end

  # --- skip and pause ---

  # See "How a song ends" at the top of this file
  def skip_locked(state, guild_id, later)
    return false if state.queue.current.nil? || state.skipping

    if state.song_sent
      @bridge.send_command('stop', guild: guild_id)
      state.skipping = true
    else
      move_on(state, guild_id, later, :skipped)
    end
    true
  end

  # Sends pause or resume. false when no song is at Node or it is already like that
  def change_pause(state, guild_id, paused, later)
    return false unless state.song_sent && state.queue.paused != paused

    @bridge.send_command(paused ? 'pause' : 'resume', guild: guild_id)
    state.queue.paused = paused
    later << -> { refresh_panel(guild_id) }
    true
  end

  # --- events ---

  def event_locked(state, guild_id, name, reason, later)
    case name
    when 'joined' then state.joined = true
    when 'finished' then song_ended(state, guild_id, later)
    when 'failed' then failed_event(state, guild_id, reason, later)
    when 'disconnected' then reset_server(state, guild_id, later) # Node already left and dropped the song
    end
  end

  # The current song is over: play the next one (or the same one, when it loops).
  # It ended because of a skip when `skipping` is set (Node answers a stop with "finished").
  # A song that ended normally means playing works, so the failure count starts again
  def song_ended(state, guild_id, later)
    return unless state.song_sent # left over from a stopped song: Node has nothing of ours

    state.failures_in_a_row = 0
    move_on(state, guild_id, later, state.skipping ? :skipped : :finished)
  end

  # Joining failed (before "joined"): give up on this server with one message.
  # Otherwise the song could not play: say so and play the next one
  def failed_event(state, guild_id, reason, later)
    log "🎵 Node failed in server #{guild_id}: #{reason}"
    if !state.joined && state.voice_channel_id && reason == MUSIC_JOIN_FAILURE
      note(state, later, '❗ Could not join the voice channel.')
      return reset_server(state, guild_id, later)
    end
    return unless state.song_sent

    song_failed(state, guild_id, "❗ Could not play #{state.queue.current.title}, skipping.", later)
  end

  # A song could not be played or found: a short note that deletes itself, then the next song.
  # When MUSIC_MAX_FAILURES_IN_A_ROW songs fail one after another, something is broken
  # (often an old yt-dlp), so the music stops with one message instead of a note for every song
  def song_failed(state, guild_id, text, later)
    state.failures_in_a_row += 1
    return give_up_after_failures(state, guild_id, later) if state.failures_in_a_row >= MUSIC_MAX_FAILURES_IN_A_ROW

    temporary_note(state, later, text)
    move_on(state, guild_id, later)
  end

  # Too many failures in a row: one message that stays, then stop like !stop
  def give_up_after_failures(state, guild_id, later)
    log "🎵 #{MUSIC_MAX_FAILURES_IN_A_ROW} songs failed in a row in server #{guild_id}, stopping"
    note(state, later, MUSIC_TOO_MANY_FAILURES_TEXT)
    stop_locked(state, guild_id, later)
  end

  # Stops the song at Node, leaves voice and forgets the queue (the panel turns to "stopped")
  def stop_locked(state, guild_id, later)
    @bridge.send_command('stop', guild: guild_id)
    @bridge.send_command('leave', guild: guild_id)
    reset_server(state, guild_id, later)
  end

  # Node stopped: every server lost its voice connection
  def reset_every_server
    with_lock('node_stopped') do |later|
      @servers.each do |guild_id, state|
        reset_server(state, guild_id, later) if state.active?
      end
    end
  end

  def reset_server(state, guild_id, later)
    state.reset!
    later << -> { stop_panel(guild_id) }
  end

  # --- leaving when idle ---

  # Nothing left to play: the panel turns to "stopped" now (the next !play posts a fresh one),
  # and Cake leaves after MUSIC_IDLE_LEAVE_SECONDS unless a new song comes first
  def start_idle_wait(state, guild_id, later)
    later << -> { stop_panel(guild_id) }
    return if state.voice_channel_id.nil?

    token = Object.new
    state.idle_token = token
    later << -> { @scheduler.call(MUSIC_IDLE_LEAVE_SECONDS) { idle_wait_over(guild_id, token) } }
  end

  def idle_wait_over(guild_id, token)
    with_lock('idle leave') do |later|
      state = @servers[guild_id]
      next unless state && state.idle_token.equal?(token) && state.queue.current.nil?

      @bridge.send_command('leave', guild: guild_id)
      reset_server(state, guild_id, later)
    end
  end

  # --- safety ---

  # Runs the block under @lock; the block adds Discord work to `later`, which runs after the lock
  # is released. Never raises: a failure is logged and `fallback` is returned
  def with_lock(action, fallback = nil)
    later = []
    result = @lock.synchronize { yield later }
    later.each { |work| safely(action) { work.call } }
    result
  rescue StandardError => e
    log "🎵 #{action} failed: #{e.message}"
    fallback
  end

  # Runs the block; a failure is logged and `fallback` is returned
  def safely(action, fallback = nil)
    yield
  rescue StandardError => e
    log "🎵 #{action} failed: #{e.message}"
    fallback
  end
end
