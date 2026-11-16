require_relative "test_helper"
require_relative "../music_controller"

# Pretends to be the bridge to Node: remembers every command, always ready
class FakeBridge
  attr_reader :ops, :volumes

  def initialize
    @ops = []
    @volumes = [] # [op, guild, volume] for every command that carried a volume
    @ops_lock = Mutex.new
  end

  def ready? = true

  # ["join", 1, 10], ["play", 1, "u/a"], ["leave", 1] ...
  # The volume is kept apart in `volumes`, so the older tests can compare ops as before.
  def send_command(op, guild:, **fields)
    @ops_lock.synchronize do
      @volumes << [op, guild, fields[:volume]] if fields.key?(:volume)
      @ops << [op, guild, *fields.except(:volume).values] unless op == "volume"
    end
    true
  end
end

# Pretends to be the panel poster: remembers which servers got a panel shown or stopped
class FakePoster
  attr_reader :shows, :stops

  def initialize
    @shows = []
    @stops = []
  end

  def show(guild_id, _channel, embed, _view)
    @shows << [guild_id, embed.title]
  end

  def stop(guild_id)
    @stops << guild_id
  end
end

# Pretends to be a text channel: remembers the notes Cake posts (messages stay, temporary ones delete themselves)
class FakeTextChannel
  attr_reader :messages, :temporary

  def initialize
    @messages = []
    @temporary = []
  end

  def send_message(text)
    @messages << text
  end

  def send_temporary_message(text, seconds)
    @temporary << [text, seconds]
  end
end

# Keeps the scheduled blocks; the test runs them when it wants ("time passes")
class StoredScheduler
  def initialize
    @blocks = []
  end

  def call(_seconds, &block)
    @blocks << block
  end

  def run_all
    blocks = @blocks
    @blocks = []
    blocks.each(&:call)
  end
end

class MusicControllerTest < Minitest::Test
  def setup
    @bridge = FakeBridge.new
    @poster = FakePoster.new
    @channel = FakeTextChannel.new
    @scheduler = StoredScheduler.new
    @resolver = ->(t) { t.dup.tap { |copy| copy.url = "resolved/#{t.search}" } }
    @music = MusicController.new(bridge: @bridge, poster: @poster,
                                 resolver: ->(t) { @resolver.call(t) }, scheduler: @scheduler)
  end

  def track(title, playlist = nil)
    MusicTrack.new(title: title, url: "u/#{title}", playlist_id: playlist, playlist_name: playlist, requester_id: 5)
  end

  def spotify(title)
    MusicTrack.new(title: title, search: "#{title} x", url: nil, requester_id: 5)
  end

  # Waits (at most 2 seconds) for the resolver thread to do something
  def wait_until
    deadline = Time.now + 2
    until yield
      flunk "timed out waiting" if Time.now > deadline
      sleep 0.01
    end
  end

  # --- tests from the brief ---

  def test_first_play_joins_and_starts
    assert_equal :started, @music.play(1, 10, @channel, [track("a")])
    assert_equal [["join", 1, 10], ["play", 1, "u/a"]], @bridge.ops
    assert_equal 1, @poster.shows.length
  end

  def test_second_play_queues
    @music.play(1, 10, @channel, [track("a")])
    assert_equal :queued, @music.play(1, 10, @channel, [track("b")])
    assert_equal 1, @music.queue_snapshot(1).last.length
  end

  def test_finished_plays_next
    @music.play(1, 10, @channel, [track("a"), track("b")])
    @music.handle_event("event" => "finished", "guild" => "1")
    assert_equal ["play", 1, "u/b"], @bridge.ops.last
  end

  def test_double_skip_advances_once
    @music.play(1, 10, @channel, [track("a"), track("b"), track("c")])
    @music.skip(1); @music.skip(1)
    @music.handle_event("event" => "finished", "guild" => "1")
    assert_equal "b", @music.queue_snapshot(1).first.title
  end

  def test_idle_then_leave
    @music.play(1, 10, @channel, [track("a")])
    @music.handle_event("event" => "finished", "guild" => "1")
    @scheduler.run_all
    assert_equal ["leave", 1], @bridge.ops.last
    assert_includes @poster.stops, 1
  end

  # The panel says "stopped" as soon as the queue runs out, not only when Cake leaves
  def test_queue_running_out_stops_panel_at_once
    @music.play(1, 10, @channel, [track("a")])
    @music.handle_event("event" => "finished", "guild" => "1")
    assert_equal [1], @poster.stops
    refute_includes @bridge.ops, ["leave", 1] # still waiting in voice
  end

  # A new !play during the idle wait gets a fresh panel
  def test_play_after_idle_shows_panel_again
    @music.play(1, 10, @channel, [track("a")])
    @music.handle_event("event" => "finished", "guild" => "1")
    shows = @poster.shows.length
    @music.play(1, 10, @channel, [track("b")])
    assert_equal shows + 1, @poster.shows.length
  end

  def test_play_during_idle_wait_cancels_leave
    @music.play(1, 10, @channel, [track("a")])
    @music.handle_event("event" => "finished", "guild" => "1")
    @music.play(1, 10, @channel, [track("b")])
    @scheduler.run_all
    refute_includes @bridge.ops, ["leave", 1]
  end

  def test_idle_in_other_channel_moves
    @music.play(1, 10, @channel, [track("a")])
    @music.handle_event("event" => "finished", "guild" => "1")
    assert_equal :moved_and_started, @music.play(1, 20, @channel, [track("b")])
    assert_includes @bridge.ops, ["join", 1, 20]
  end

  def test_spotify_track_resolved_at_its_turn
    pending = MusicTrack.new(title: "S", search: "S x", url: nil)
    @music.play(1, 10, @channel, [pending])
    wait_until { @bridge.ops.last&.first == "play" }
    assert_equal ["play", 1, "resolved/S x"], @bridge.ops.last
  end

  def test_failed_posts_note_and_moves_on
    @music.play(1, 10, @channel, [track("a"), track("b")])
    @music.handle_event("event" => "failed", "guild" => "1", "reason" => "403")
    assert_equal [["❗ Could not play a, skipping.", MUSIC_NOTE_SECONDS]], @channel.temporary
    assert_empty @channel.messages
    assert_equal ["play", 1, "u/b"], @bridge.ops.last
  end

  # --- too many failures in a row ---

  def fail_current_song
    @music.handle_event("event" => "failed", "guild" => "1", "reason" => "403")
  end

  def test_three_failures_in_a_row_stop_the_music
    @music.play(1, 10, @channel, [track("a"), track("b"), track("c"), track("d")])
    3.times { fail_current_song }
    assert_equal 2, @channel.temporary.length
    assert_equal ["❗ 3 songs in a row failed, so I stopped. yt-dlp may need an update (`yt-dlp -U`)."], @channel.messages
    assert_equal [["stop", 1], ["leave", 1]], @bridge.ops.last(2)
    refute_includes @bridge.ops, ["play", 1, "u/d"]
    refute @music.busy?(1)
    assert_equal [1], @poster.stops
  end

  def test_a_song_that_plays_to_the_end_resets_the_failure_count
    @music.play(1, 10, @channel, [track("a"), track("b"), track("c"), track("d"), track("e"), track("f")])
    2.times { fail_current_song }
    @music.handle_event("event" => "finished", "guild" => "1") # c played fine
    2.times { fail_current_song }
    assert_empty @channel.messages
    assert_equal "f", @music.queue_snapshot(1).first.title # d and e failed, but only 2 in a row
  end

  def test_spotify_songs_not_found_count_as_failures
    @resolver = ->(_t) { nil }
    @music.play(1, 10, @channel, [spotify("S1"), spotify("S2"), spotify("S3"), track("b")])
    wait_until { @channel.messages.any? }
    assert_equal 2, @channel.temporary.length
    refute_includes @bridge.ops, ["play", 1, "u/b"]
    refute @music.busy?(1)
  end

  def test_a_new_play_after_giving_up_starts_counting_again
    @music.play(1, 10, @channel, [track("a"), track("b"), track("c")])
    3.times { fail_current_song }
    @music.play(1, 10, @channel, [track("x"), track("y")])
    fail_current_song
    assert_equal ["play", 1, "u/y"], @bridge.ops.last
  end

  def test_node_stopped_resets_every_server
    @music.play(1, 10, @channel, [track("a")])
    @music.play(2, 30, @channel, [track("b")])
    @music.handle_event("event" => "node_stopped")
    refute @music.busy?(1)
    refute @music.busy?(2)
    assert_equal [1, 2], @poster.stops.sort
  end

  def test_skip_playlist_skips_current_and_its_playlist
    @music.play(1, 10, @channel, [track("p1", "P"), track("p2", "P"), track("solo")])
    assert_equal 1, @music.skip_playlist(1)
    @music.handle_event("event" => "finished", "guild" => "1")
    assert_equal "solo", @music.queue_snapshot(1).first.title
  end

  def test_everyone_left_stops
    @music.play(1, 10, @channel, [track("a")])
    @music.listeners_changed(1, 0)
    assert_equal ["leave", 1], @bridge.ops.last
  end

  # --- ruling 1: skip before Node has the song ---

  def test_skip_while_spotify_song_is_resolving_advances_at_once
    gate = Queue.new
    @resolver = ->(t) { gate.pop; t.dup.tap { |copy| copy.url = "resolved/#{t.search}" } }
    @music.play(1, 10, @channel, [spotify("S"), track("b")])
    assert @music.skip(1)
    assert_equal ["play", 1, "u/b"], @bridge.ops.last
    gate << :go # the search for the skipped song ends now; it must not be played
    sleep 0.05
    refute(@bridge.ops.any? { |op| op[2].to_s.start_with?("resolved/") })
    assert_equal "b", @music.queue_snapshot(1).first.title
  end

  def test_skip_after_play_was_sent_waits_for_finished
    @music.play(1, 10, @channel, [track("a"), track("b")])
    assert @music.skip(1)
    assert_equal ["stop", 1], @bridge.ops.last
    assert_equal "a", @music.queue_snapshot(1).first.title
    @music.handle_event("event" => "finished", "guild" => "1")
    assert_equal ["play", 1, "u/b"], @bridge.ops.last
  end

  def test_stray_finished_with_no_song_at_node_is_ignored
    @music.play(1, 10, @channel, [track("a"), track("b"), track("c")])
    @music.handle_event("event" => "finished", "guild" => "1")
    @music.stop(1)
    @music.handle_event("event" => "finished", "guild" => "1") # the stop's finished, after leaving
    refute @music.busy?(1)
    assert_equal ["leave", 1], @bridge.ops.last
  end

  def test_stray_finished_while_searching_does_not_skip
    gate = Queue.new
    @resolver = ->(t) { gate.pop; t.dup.tap { |copy| copy.url = "resolved/#{t.search}" } }
    @music.play(1, 10, @channel, [track("a"), spotify("S"), track("c")])
    @music.handle_event("event" => "finished", "guild" => "1") # a ends, S is being searched
    @music.handle_event("event" => "finished", "guild" => "1") # nothing of ours at Node: ignore
    assert_equal "S", @music.queue_snapshot(1).first.title
    gate << :go
    wait_until { @bridge.ops.last == ["play", 1, "resolved/S x"] }
  end

  def test_spotify_song_not_found_posts_note_and_moves_on
    @resolver = ->(_t) { nil }
    @music.play(1, 10, @channel, [spotify("S"), track("b")])
    wait_until { @bridge.ops.last == ["play", 1, "u/b"] }
    assert_includes @channel.temporary, ["❗ Couldn't find \"S x\" on YouTube, skipping.", MUSIC_NOTE_SECONDS]
  end

  # --- ruling 2: disconnected ---

  def test_disconnected_resets_server_and_stops_panel
    @music.play(1, 10, @channel, [track("a"), track("b")])
    @music.handle_event("event" => "disconnected", "guild" => "1")
    refute @music.busy?(1)
    assert_nil @music.voice_channel_id(1)
    assert_equal [1], @poster.stops
    assert_equal :started, @music.play(1, 10, @channel, [track("c")])
  end

  # --- ruling 3: join failure ---

  def test_join_failure_resets_and_posts_one_message
    @music.play(1, 10, @channel, [track("a"), track("b"), track("c")])
    @music.handle_event("event" => "failed", "guild" => "1", "reason" => "could not join the voice channel")
    @music.handle_event("event" => "failed", "guild" => "1", "reason" => "not connected to a voice channel")
    refute @music.busy?(1)
    assert_equal ["❗ Could not join the voice channel."], @channel.messages
    assert_equal [1], @poster.stops
  end

  def test_join_failure_reason_after_joined_is_a_song_failure
    @music.play(1, 10, @channel, [track("a"), track("b")])
    @music.handle_event("event" => "joined", "guild" => "1")
    @music.handle_event("event" => "failed", "guild" => "1", "reason" => "could not join the voice channel")
    assert_equal ["play", 1, "u/b"], @bridge.ops.last
  end

  # --- pause, clear, stop, safety ---

  def test_toggle_and_set_paused
    assert_nil @music.toggle_pause(1)
    @music.play(1, 10, @channel, [track("a")])
    assert_equal :paused, @music.toggle_pause(1)
    refute @music.set_paused(1, true)
    assert @music.set_paused(1, false)
    assert_equal [["pause", 1], ["resume", 1]], @bridge.ops.last(2)
    assert_equal "🎵 Now playing", @poster.shows.last.last
  end

  def test_clear_queue_keeps_current
    @music.play(1, 10, @channel, [track("a"), track("b"), track("c")])
    assert_equal 2, @music.clear_queue(1)
    assert_equal ["a", []], [@music.queue_snapshot(1).first.title, @music.queue_snapshot(1).last]
  end

  def test_stop_sends_stop_and_leave
    @music.play(1, 10, @channel, [track("a")])
    @music.stop(1)
    assert_equal [["stop", 1], ["leave", 1]], @bridge.ops.last(2)
    assert_equal [1], @poster.stops
    refute @music.busy?(1)
  end

  def test_failing_discord_note_does_not_break_controller
    def @channel.send_temporary_message(_text, _seconds) = raise("discord down")
    @music.play(1, 10, @channel, [track("a"), track("b")])
    @music.handle_event("event" => "failed", "guild" => "1", "reason" => "403")
    assert_equal ["play", 1, "u/b"], @bridge.ops.last
    assert(LOGS.any? { |line| line.include?("🎵") && line.include?("discord down") })
  end

  def test_bad_events_never_raise
    @music.handle_event("event" => "finished", "guild" => "nope")
    @music.handle_event("event" => "finished", "guild" => "99")
    @music.handle_event({})
    assert_equal [nil, []], @music.queue_snapshot(99)
  end

  # --- volume ---

  def test_play_sends_the_default_volume
    @music.play(1, 10, @channel, [track("a")])
    assert_equal [["play", 1, MUSIC_DEFAULT_VOLUME]], @bridge.volumes
    assert_equal MUSIC_DEFAULT_VOLUME, @music.volume(1)
  end

  def test_set_volume_sends_it_right_away_and_clamps
    @music.play(1, 10, @channel, [track("a")])
    assert_equal 30, @music.set_volume(1, 30)
    assert_equal 100, @music.set_volume(1, 250)
    assert_equal 0, @music.set_volume(1, -4)
    assert_equal [["volume", 1, 30], ["volume", 1, 100], ["volume", 1, 0]], @bridge.volumes.last(3)
  end

  def test_change_volume_steps_from_the_current_level
    @music.play(1, 10, @channel, [track("a")])
    assert_equal MUSIC_DEFAULT_VOLUME - 10, @music.change_volume(1, -10)
    assert_equal MUSIC_DEFAULT_VOLUME, @music.change_volume(1, 10)
  end

  def test_volume_is_kept_for_the_next_song
    @music.play(1, 10, @channel, [track("a"), track("b")])
    @music.set_volume(1, 20)
    @music.handle_event("event" => "finished", "guild" => "1")
    assert_equal ["play", 1, 20], @bridge.volumes.last
  end

  def test_volume_goes_back_to_default_after_stop
    @music.play(1, 10, @channel, [track("a")])
    @music.set_volume(1, 20)
    @music.stop(1)
    @music.play(1, 10, @channel, [track("b")])
    assert_equal ["play", 1, MUSIC_DEFAULT_VOLUME], @bridge.volumes.last
  end

  def test_volume_when_cake_is_not_in_voice
    assert_nil @music.set_volume(1, 30)
    assert_nil @music.change_volume(1, 10)
    assert_nil @music.volume(1)
    assert_empty @bridge.volumes
  end

  def test_panel_shows_the_volume
    @music.play(1, 10, @channel, [track("a")])
    @music.set_volume(1, 40)
    assert_equal 2, @poster.shows.length
  end
end
