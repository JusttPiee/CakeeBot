require_relative "test_helper"
require_relative "music_permissions_test" # FakeVoiceChannel, FakeVoiceState
require_relative "../music_commands"

CommandTrack = Struct.new(:title, :duration, :playlist_name)

# Records what the controller was asked to do. Answers are set when it is made.
class FakeController
  attr_reader :calls

  def initialize(available: true, voice_channel: nil, busy: false, play_result: :started, toggle_result: :paused, skip_result: true)
    @available = available
    @voice_channel = voice_channel
    @busy = busy
    @play_result = play_result
    @toggle_result = toggle_result
    @skip_result = skip_result
    @calls = []
  end

  # Pretends someone else started music in this channel (like during a slow search)
  def start_elsewhere(channel_id)
    @voice_channel = channel_id
    @busy = true
  end

  def available? = @available
  def voice_channel_id(_guild_id) = @voice_channel
  def busy?(_guild_id) = @busy
  def queue_snapshot(_guild_id) = [CommandTrack.new("Now song"), [CommandTrack.new("Next song")]]

  def play(guild_id, voice_id, _text_channel, tracks)
    @calls << [:play, guild_id, voice_id, tracks.length]
    @play_result
  end

  def toggle_pause(_guild_id) = record(:toggle_pause, @toggle_result)
  def set_paused(_guild_id, paused) = record([:set_paused, paused], true)
  def skip(_guild_id) = record(:skip, @skip_result)
  def skip_playlist(_guild_id) = record(:skip_playlist, 0)
  def clear_queue(_guild_id) = record(:clear_queue, 0)
  def stop(_guild_id) = record(:stop, nil)
  def volume(_guild_id) = @voice_channel ? 50 : nil
  def set_volume(_guild_id, level) = record([:set_volume, level], @voice_channel ? level.clamp(0, 100) : nil)
  def change_volume(_guild_id, step) = record([:change_volume, step], @voice_channel ? 50 + step : nil)

  private

  def record(name, result)
    @calls << name
    result
  end
end

# A text channel: remembers temporary notes
class CommandChannel
  attr_reader :temporary

  def initialize
    @temporary = []
  end

  def send_temporary_message(text, seconds)
    @temporary << [text, seconds]
  end
end

CommandServer = Struct.new(:id, :voice_states)
CommandVoiceUser = Struct.new(:id, :admin) do
  def permission?(_permission) = admin ? true : false
end

# A !command event: the user is in voice channel `voice` (nil = not in voice)
class MusicCommandEvent
  attr_reader :server, :user, :channel, :responses

  def initialize(voice, admin: false)
    states = voice ? { 5 => FakeVoiceState.new(FakeVoiceChannel.new(voice)) } : {}
    @server = CommandServer.new(1, states)
    @user = CommandVoiceUser.new(5, admin)
    @channel = CommandChannel.new
    @responses = []
  end

  def respond(text)
    @responses << text
    nil
  end
end

# A button event: responses keep the keyword arguments, like discordrb's
class MusicButtonEvent < MusicCommandEvent
  attr_reader :custom_id, :deferred, :followups

  def initialize(custom_id, voice, admin: false)
    super(voice, admin: admin)
    @custom_id = custom_id
    @deferred = false
    @followups = []
  end

  def respond(content:, ephemeral:)
    @responses << { content: content, ephemeral: ephemeral }
    nil
  end

  def defer_update
    @deferred = true
  end

  # A follow-up message after defer_update (discordrb: event.send_message)
  def send_message(content:, ephemeral:)
    @followups << { content: content, ephemeral: ephemeral }
    nil
  end
end

FoundSongs = Struct.new(:tracks, :error, :cut_off)

# Pretends to be the controller for voice updates: remembers who it heard about
class ListenerController
  attr_reader :heard

  def initialize(channel)
    @channel = channel
    @heard = []
  end

  def voice_channel_id(_guild_id) = @channel
  def listeners_changed(guild_id, count) = @heard << [guild_id, count]
  def stop(guild_id) = @heard << [:stop, guild_id]
end

VoiceMember = Struct.new(:bot_account?)
VoiceRoom = Struct.new(:id, :users)
VoiceEvent = Struct.new(:server, :channel, :old_channel, :user, :bot)
VoiceUser = Struct.new(:id)
VoiceBot = Struct.new(:profile)
CAKE_ID = 777

class MusicCommandsTest < Minitest::Test
  NO_PARTS_MISSING = -> { [] }

  def run_command(event, action, args, controller, finder: nil, parts: NO_PARTS_MISSING)
    options = { parts: parts }
    options[:finder] = finder if finder
    music_command(event, action, args, controller, **options)
  end

  def found(count, playlist: nil, cut_off: false, error: nil)
    tracks = Array.new(count) { |i| CommandTrack.new("Song #{i + 1}", 100, playlist) }
    FoundSongs.new(error ? [] : tracks, error, cut_off)
  end

  def test_play_when_unavailable
    event = MusicCommandEvent.new(10)
    run_command(event, :play, ["x"], FakeController.new(available: false))
    assert_includes event.channel.temporary.first.first, "Music is not available"
    assert_equal 10, event.channel.temporary.first.last
  end

  def test_play_when_parts_are_missing
    event = MusicCommandEvent.new(10)
    run_command(event, :play, ["x"], FakeController.new, parts: -> { ["yt-dlp"] })
    assert_includes event.channel.temporary.first.first, "Music is not available"
  end

  def test_play_returns_nil
    event = MusicCommandEvent.new(10)
    assert_nil run_command(event, :play, ["x"], FakeController.new, finder: ->(*) { found(1) })
  end

  def test_play_without_text_shows_usage
    event = MusicCommandEvent.new(10)
    run_command(event, :play, [], FakeController.new)
    assert_equal "Usage: `!play <link or song name>`", event.responses.last
  end

  def test_permission_problem_comes_before_the_slow_search
    event = MusicCommandEvent.new(nil)
    searched = false
    run_command(event, :play, ["x"], FakeController.new, finder: ->(*) { searched = true; found(1) })
    refute searched
    assert_equal "🎧 Join a voice channel first.", event.channel.temporary.first.first
  end

  # The user leaves voice while the (slow) search runs
  def test_user_left_voice_during_the_search
    event = MusicCommandEvent.new(10)
    controller = FakeController.new
    finder = ->(*) { event.server.voice_states.clear; found(1) }
    run_command(event, :play, ["x"], controller, finder: finder)
    assert_empty controller.calls
    assert_equal "🎧 Join a voice channel first.", event.channel.temporary.first.first
  end

  # Someone else starts music in another channel while the search runs
  def test_cake_became_busy_elsewhere_during_the_search
    event = MusicCommandEvent.new(10)
    controller = FakeController.new
    finder = ->(*) { controller.start_elsewhere(20); found(1) }
    run_command(event, :play, ["x"], controller, finder: finder)
    assert_empty controller.calls
    assert_equal "🎵 Cake is playing in <#20>.", event.channel.temporary.first.first
  end

  def test_search_error_is_the_reply
    event = MusicCommandEvent.new(10)
    controller = FakeController.new
    run_command(event, :play, ["x"], controller, finder: ->(*) { found(0, error: "I could not find that song.") })
    assert_equal "I could not find that song.", event.responses.last
    assert_empty controller.calls
  end

  def test_started_has_no_extra_message
    event = MusicCommandEvent.new(10)
    controller = FakeController.new(play_result: :started)
    run_command(event, :play, ["x"], controller, finder: ->(*) { found(1) })
    assert_empty event.responses
    assert_equal [[:play, 1, 10, 1]], controller.calls
  end

  def test_queued_single_song_reply
    event = MusicCommandEvent.new(10)
    run_command(event, :play, ["x"], FakeController.new(play_result: :queued), finder: ->(*) { found(1) })
    assert_equal "➕ Added Song 1", event.responses.last
  end

  def test_play_queued_reply_mentions_playlist_cut
    event = MusicCommandEvent.new(10)
    controller = FakeController.new(play_result: :queued)
    run_command(event, :play, ["url"], controller, finder: ->(*) { found(3, playlist: "Mix", cut_off: true) })
    assert_match(/Added 3 songs from Mix .*only the first #{MUSIC_PLAYLIST_LIMIT}/, event.responses.last)
  end

  # A playlist pasted when nothing plays: still say how many songs were added and that it was cut
  def test_playlist_that_starts_fresh_says_how_many_were_added
    event = MusicCommandEvent.new(10)
    controller = FakeController.new(play_result: :started)
    run_command(event, :play, ["url"], controller, finder: ->(*) { found(3, playlist: "Mix", cut_off: true) })
    assert_equal "➕ Added 3 songs from Mix (only the first #{MUSIC_PLAYLIST_LIMIT})", event.responses.last
  end

  def test_one_cut_song_that_starts_fresh_still_says_it_was_cut
    event = MusicCommandEvent.new(10)
    run_command(event, :play, ["url"], FakeController.new(play_result: :started), finder: ->(*) { found(1, cut_off: true) })
    assert_equal "➕ Added Song 1 (only the first #{MUSIC_PLAYLIST_LIMIT})", event.responses.last
  end

  def test_queued_playlist_reply_without_cut
    event = MusicCommandEvent.new(10)
    run_command(event, :play, ["url"], FakeController.new(play_result: :queued), finder: ->(*) { found(3, playlist: "Mix") })
    assert_equal "➕ Added 3 songs from Mix", event.responses.last
  end

  def test_mentions_in_titles_do_not_ping
    event = MusicCommandEvent.new(10)
    finder = ->(*) { FoundSongs.new([CommandTrack.new("@everyone", 1, nil)], nil, false) }
    run_command(event, :play, ["x"], FakeController.new(play_result: :queued), finder: finder)
    refute_includes event.responses.last, "@everyone"
  end

  def test_skip_from_outside_voice_is_refused
    event = MusicCommandEvent.new(nil)
    controller = FakeController.new(voice_channel: 20)
    run_command(event, :skip, [], controller)
    assert_equal "🎧 Join <#20> to control the music.", event.channel.temporary.first.first
    assert_empty controller.calls
  end

  def test_skip_in_the_same_channel
    event = MusicCommandEvent.new(20)
    controller = FakeController.new(voice_channel: 20)
    assert_nil run_command(event, :skip, [], controller)
    assert_equal [:skip], controller.calls
  end

  def test_pause_and_resume
    event = MusicCommandEvent.new(20)
    controller = FakeController.new(voice_channel: 20)
    run_command(event, :pause, [], controller)
    run_command(event, :resume, [], controller)
    assert_equal [[:set_paused, true], [:set_paused, false]], controller.calls
  end

  def test_admin_stops_from_outside_voice
    event = MusicCommandEvent.new(nil, admin: true)
    controller = FakeController.new(voice_channel: 20)
    run_command(event, :stop, [], controller)
    assert_equal [:stop], controller.calls
  end

  def test_queue_is_a_normal_message
    event = MusicCommandEvent.new(20)
    run_command(event, :queue, [], FakeController.new(voice_channel: 20))
    assert_includes event.responses.last, "Now: Now song"
    assert_includes event.responses.last, "Next song"
  end

  def test_a_crash_is_logged_and_nothing_escapes
    event = MusicCommandEvent.new(10)
    LOGS.clear
    broken = ->(*) { raise "boom" }
    assert_nil run_command(event, :play, ["x"], FakeController.new, finder: broken)
    assert(LOGS.any? { |line| line.start_with?("🎵") })
  end

  def test_queue_text_stays_under_discord_limit
    long = Array.new(50) { |i| CommandTrack.new("x" * 200 + i.to_s, 10, nil) }
    text = music_queue_message(CommandTrack.new("Now", 1, nil), long)
    assert_operator text.length, :<=, 2000
  end

  # --- buttons ---

  def test_button_from_outside_voice_is_private
    event = MusicButtonEvent.new("music:skip", nil)
    controller = FakeController.new(voice_channel: 20)
    assert_nil music_button(event, controller, parts: NO_PARTS_MISSING)
    assert event.responses.last[:ephemeral]
    assert_empty controller.calls
  end

  def test_queue_button_is_private
    event = MusicButtonEvent.new("music:queue", 20)
    music_button(event, FakeController.new(voice_channel: 20), parts: NO_PARTS_MISSING)
    assert event.responses.last[:ephemeral]
    assert_includes event.responses.last[:content], "Next song"
  end

  def test_toggle_button_acknowledges_quietly
    event = MusicButtonEvent.new("music:toggle", 20)
    controller = FakeController.new(voice_channel: 20)
    music_button(event, controller, parts: NO_PARTS_MISSING)
    assert_equal [:toggle_pause], controller.calls
    assert event.deferred
    assert_empty event.responses
  end

  # Discord gets its answer before the action runs; "nothing to do" comes after as a private follow-up
  def test_button_defers_before_the_action_and_follows_up_privately
    event = MusicButtonEvent.new("music:toggle", 20)
    controller = FakeController.new(voice_channel: 20, toggle_result: nil)
    deferred_when_called = nil
    controller.define_singleton_method(:toggle_pause) do |_guild_id|
      deferred_when_called = event.deferred
      nil
    end
    music_button(event, controller, parts: NO_PARTS_MISSING)
    assert deferred_when_called
    assert_empty event.responses
    assert_equal [{ content: "🎵 Nothing is playing.", ephemeral: true }], event.followups
  end

  def test_every_button_maps_to_an_action
    { "music:skip" => :skip, "music:skipplaylist" => :skip_playlist, "music:clearqueue" => :clear_queue }.each do |id, call|
      event = MusicButtonEvent.new(id, 20)
      controller = FakeController.new(voice_channel: 20)
      music_button(event, controller, parts: NO_PARTS_MISSING)
      assert_equal [call], controller.calls
    end
  end

  def test_volume_buttons_step_the_volume
    { "music:voldown" => [:change_volume, -MUSIC_VOLUME_STEP], "music:volup" => [:change_volume, MUSIC_VOLUME_STEP] }.each do |id, call|
      event = MusicButtonEvent.new(id, 20)
      controller = FakeController.new(voice_channel: 20)
      music_button(event, controller, parts: NO_PARTS_MISSING)
      assert_equal [call], controller.calls
      assert event.deferred
      assert_empty event.followups
    end
  end

  def test_volume_button_from_outside_voice_is_refused
    event = MusicButtonEvent.new("music:volup", nil)
    controller = FakeController.new(voice_channel: 20)
    music_button(event, controller, parts: NO_PARTS_MISSING)
    assert_empty controller.calls
    assert event.responses.last[:ephemeral]
  end

  # --- !volume ---

  def test_volume_command_sets_the_level
    event = MusicCommandEvent.new(20)
    controller = FakeController.new(voice_channel: 20)
    run_command(event, :volume, ["30"], controller)
    assert_equal [[:set_volume, 30]], controller.calls
    assert_equal ["🔊 Volume: 30%"], event.channel.temporary.map(&:first)
  end

  def test_volume_command_without_a_number_shows_the_level
    event = MusicCommandEvent.new(20)
    controller = FakeController.new(voice_channel: 20)
    run_command(event, :volume, [], controller)
    assert_empty controller.calls
    assert_equal ["🔊 Volume: 50%"], event.channel.temporary.map(&:first)
  end

  def test_volume_command_with_a_bad_number_shows_usage
    event = MusicCommandEvent.new(20)
    controller = FakeController.new(voice_channel: 20)
    run_command(event, :volume, ["loud"], controller)
    assert_empty controller.calls
    assert_equal ["Usage: `!volume <0-100>`"], event.channel.temporary.map(&:first)
  end

  def test_volume_command_needs_cakes_voice_channel
    event = MusicCommandEvent.new(10)
    controller = FakeController.new(voice_channel: 20)
    run_command(event, :volume, ["30"], controller)
    assert_empty controller.calls
  end

  def test_button_when_unavailable_is_private
    event = MusicButtonEvent.new("music:skip", 20)
    music_button(event, FakeController.new(available: false, voice_channel: 20), parts: NO_PARTS_MISSING)
    assert_includes event.responses.last[:content], "not available"
    assert event.responses.last[:ephemeral]
  end

  # --- voice updates ---

  def test_leaving_cakes_channel_counts_humans_left
    controller = ListenerController.new(20)
    room = VoiceRoom.new(20, [VoiceMember.new(true)])
    music_voice_update(VoiceEvent.new(CommandServer.new(1, {}), nil, room), controller)
    assert_equal [[1, 0]], controller.heard
  end

  def test_other_channels_are_ignored
    controller = ListenerController.new(20)
    room = VoiceRoom.new(30, [])
    music_voice_update(VoiceEvent.new(CommandServer.new(1, {}), room, nil), controller)
    assert_empty controller.heard
  end

  # --- someone drags Cake to another channel ---

  def cake_event(new_room, old_room)
    VoiceEvent.new(CommandServer.new(1, {}), new_room, old_room, VoiceUser.new(CAKE_ID), VoiceBot.new(VoiceUser.new(CAKE_ID)))
  end

  def test_cake_moved_to_another_channel_stops_the_music
    controller = ListenerController.new(20)
    music_voice_update(cake_event(VoiceRoom.new(30, []), VoiceRoom.new(20, [])), controller)
    assert_equal [[:stop, 1]], controller.heard
  end

  # Ruby remembers the new channel before Node joins it, so Cake's own join is not a "move"
  def test_cake_joining_the_channel_ruby_chose_is_not_a_move
    controller = ListenerController.new(30)
    music_voice_update(cake_event(VoiceRoom.new(30, [VoiceMember.new(false)]), VoiceRoom.new(20, [])), controller)
    refute_includes controller.heard, [:stop, 1]
  end

  # Cake left voice entirely: Node sends "disconnected", so nothing is done here
  def test_cake_leaving_voice_is_not_a_move
    controller = ListenerController.new(20)
    music_voice_update(cake_event(nil, VoiceRoom.new(20, [])), controller)
    refute_includes controller.heard, [:stop, 1]
  end

  def test_cake_moving_when_not_playing_is_ignored
    controller = ListenerController.new(nil)
    music_voice_update(cake_event(VoiceRoom.new(30, []), VoiceRoom.new(20, [])), controller)
    assert_empty controller.heard
  end

  def test_someone_else_moving_is_not_cake_moving
    controller = ListenerController.new(20)
    other = VoiceEvent.new(CommandServer.new(1, {}), VoiceRoom.new(30, []), VoiceRoom.new(20, [VoiceMember.new(false)]),
                           VoiceUser.new(5), VoiceBot.new(VoiceUser.new(CAKE_ID)))
    music_voice_update(other, controller)
    assert_equal [[1, 1]], controller.heard
  end

  def test_joining_cakes_channel_counts_humans
    controller = ListenerController.new(20)
    room = VoiceRoom.new(20, [VoiceMember.new(false), VoiceMember.new(true), VoiceMember.new(false)])
    music_voice_update(VoiceEvent.new(CommandServer.new(1, {}), room, nil), controller)
    assert_equal [[1, 2]], controller.heard
  end
end
