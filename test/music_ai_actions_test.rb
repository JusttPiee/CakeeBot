require_relative "test_helper"
require_relative "music_commands_test" # FakeController, CommandTrack, CommandServer, CommandVoiceUser
require_relative "../music_ai_actions"

class MusicAiActionsTest < Minitest::Test
  NO_PARTS_MISSING = -> { [] }

  # A server where each user id sits in the given voice channel id (nil = not in voice)
  def server_with_voice(users)
    states = users.transform_values { |channel| FakeVoiceState.new(channel && FakeVoiceChannel.new(channel)) }
    CommandServer.new(1, states)
  end

  def member(id, admin: false)
    CommandVoiceUser.new(id, admin)
  end

  def channel
    CommandChannel.new
  end

  def run_action(controller, action, voice: 10, admin: false, **options)
    music_ai_action(controller, server_with_voice(5 => voice), member(5, admin: admin), channel, action,
                    parts: NO_PARTS_MISSING, **options)
  end

  def test_ai_play_refused_when_not_in_voice
    text = run_action(FakeController.new, "play", voice: nil, query: "x", finder: ->(*) { flunk })
    assert_equal "Refused: 🎧 Join a voice channel first.", text
  end

  def test_ai_play_plays_and_says_what
    controller = FakeController.new
    found = MusicFindResult.new(tracks: [CommandTrack.new("Lạc Trôi", 200, nil)])
    text = run_action(controller, "play", query: "lac troi", finder: ->(*) { found })
    assert_equal "Playing Lạc Trôi.", text
    assert_equal [:play, 1, 10, 1], controller.calls.first
  end

  def test_ai_play_says_added_when_queued
    controller = FakeController.new(play_result: :queued)
    found = MusicFindResult.new(tracks: [CommandTrack.new("Song", 200, nil)])
    assert_equal "➕ Added Song", run_action(controller, "play", query: "x", finder: ->(*) { found })
  end

  def test_ai_play_needs_a_query
    assert_equal "Refused: say what to play (a link or a song name).",
                 run_action(FakeController.new, "play", query: "  ", finder: ->(*) { flunk })
  end

  def test_ai_play_search_error
    found = MusicFindResult.new(tracks: [], error: "No results")
    assert_equal "Could not play: No results", run_action(FakeController.new, "play", query: "x", finder: ->(*) { found })
  end

  def test_ai_play_refused_when_cake_is_busy_elsewhere
    controller = FakeController.new(voice_channel: 99, busy: true)
    text = run_action(controller, "play", query: "x", finder: ->(*) { flunk })
    assert_equal "Refused: 🎵 Cake is playing in <#99>.", text
  end

  def test_ai_skip_and_nothing_to_skip
    assert_equal "Skipped.", run_action(FakeController.new(voice_channel: 10), "skip")
    assert_equal "Nothing to skip.", run_action(FakeController.new(voice_channel: 10, skip_result: false), "skip")
  end

  def test_ai_skip_playlist
    controller = FakeController.new(voice_channel: 10)
    assert_equal "Skipped the playlist (0 songs).", run_action(controller, "skip_playlist")
  end

  def test_ai_pause_and_resume
    controller = FakeController.new(voice_channel: 10)
    assert_equal "Paused.", run_action(controller, "pause")
    assert_equal "Resumed.", run_action(controller, "resume")
    assert_equal [[:set_paused, true], [:set_paused, false]], controller.calls
  end

  def test_ai_volume_down_uses_the_step
    controller = FakeController.new(voice_channel: 10)
    text = run_action(controller, "volume_down")
    assert_equal [[:change_volume, -MUSIC_VOLUME_STEP]], controller.calls
    assert_equal "Volume is now 40%.", text
  end

  def test_ai_volume_up_uses_the_step
    controller = FakeController.new(voice_channel: 10)
    assert_equal "Volume is now 60%.", run_action(controller, "volume_up")
  end

  def test_ai_set_volume
    controller = FakeController.new(voice_channel: 10)
    assert_equal "Volume is now 100%.", run_action(controller, "set_volume", level: 150)
    assert_equal [[:set_volume, 150]], controller.calls
  end

  def test_ai_set_volume_needs_a_level
    controller = FakeController.new(voice_channel: 10)
    assert_equal "Refused: give a volume from 0 to 100.", run_action(controller, "set_volume")
    assert_equal "Refused: give a volume from 0 to 100.", run_action(controller, "set_volume", level: "loud")
  end

  def test_ai_queue_shows_the_queue
    controller = FakeController.new(voice_channel: 10)
    assert_equal music_queue_message(*controller.queue_snapshot(1)), run_action(controller, "queue")
  end

  def test_ai_clear_queue
    controller = FakeController.new(voice_channel: 10)
    assert_equal "Cleared 0 songs from the queue.", run_action(controller, "clear_queue")
  end

  def test_ai_loop_modes
    { "loop_off" => ["Loop is now off.", :off], "loop_song" => ["Now looping this song.", :song],
      "loop_queue" => ["Now looping the whole queue.", :queue] }.each do |action, (text, mode)|
      controller = FakeController.new(voice_channel: 10)
      assert_equal text, run_action(controller, action)
      assert_equal [[:set_loop, mode]], controller.calls
    end
  end

  def test_ai_loop_when_nothing_plays
    controller = FakeController.new(voice_channel: 10)
    controller.define_singleton_method(:set_loop) { |_guild_id, _mode| nil }
    assert_equal "Nothing is playing.", run_action(controller, "loop_song")
  end

  def test_ai_shuffle
    controller = FakeController.new(voice_channel: 10)
    assert_equal "Nothing to shuffle.", run_action(controller, "shuffle")
    controller.shuffle_result = 3
    assert_equal "Shuffled 3 songs.", run_action(controller, "shuffle")
  end

  def test_ai_stop
    controller = FakeController.new(voice_channel: 10)
    assert_equal "Stopped the music.", run_action(controller, "stop")
    assert_equal [:stop], controller.calls
  end

  def test_ai_control_refused_outside_cakes_channel
    controller = FakeController.new(voice_channel: 10)
    assert_equal "Refused: 🎧 Join <#10> to control the music.", run_action(controller, "skip", voice: 20)
    assert_empty controller.calls
  end

  def test_ai_admin_can_stop_from_anywhere
    controller = FakeController.new(voice_channel: 10)
    assert_equal "Stopped the music.", run_action(controller, "stop", voice: nil, admin: true)
  end

  def test_ai_admin_cannot_skip_from_anywhere
    controller = FakeController.new(voice_channel: 10)
    assert_equal "Refused: 🎧 Join <#10> to control the music.", run_action(controller, "skip", voice: nil, admin: true)
  end

  def test_ai_unknown_action
    assert_equal "Unknown music action: dance.", run_action(FakeController.new, "dance")
  end

  def test_ai_music_unavailable_without_controller
    assert_equal MUSIC_UNAVAILABLE_TEXT, run_action(nil, "skip")
  end

  def test_ai_music_unavailable_when_controller_says_so
    assert_equal MUSIC_UNAVAILABLE_TEXT, run_action(FakeController.new(available: false), "skip")
  end
end
