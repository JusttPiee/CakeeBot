require_relative "test_helper"
require_relative "../music_permissions"

# A server whose voice_states say who is in which voice channel
FakeVoiceChannel = Struct.new(:id)
FakeVoiceState = Struct.new(:voice_channel)
FakeVoiceServer = Struct.new(:voice_states)

class MusicPermissionsTest < Minitest::Test
  def test_play_needs_voice
    assert_equal "🎧 Join a voice channel first.", music_play_problem(nil, nil, false)
  end

  def test_play_refused_when_busy_elsewhere
    assert_equal "🎵 Cake is playing in <#20>.", music_play_problem(10, 20, true)
  end

  def test_play_allowed_when_idle_elsewhere
    assert_nil music_play_problem(10, 20, false)
  end

  def test_play_allowed_in_the_same_channel_while_busy
    assert_nil music_play_problem(20, 20, true)
  end

  def test_control_needs_same_channel
    assert_equal "🎧 Join <#20> to control the music.", music_control_problem(10, 20, :skip, true)
  end

  def test_control_needs_cake_in_voice
    assert_equal "🎵 Nothing is playing.", music_control_problem(10, nil, :skip, false)
  end

  def test_control_allowed_in_the_same_channel
    assert_nil music_control_problem(20, 20, :skip, false)
  end

  def test_admin_may_stop_from_anywhere
    assert_nil music_control_problem(nil, 20, :stop, true)
    refute_nil music_control_problem(nil, 20, :stop, false)
  end

  def test_admin_may_not_skip_from_anywhere
    refute_nil music_control_problem(nil, 20, :skip, true)
  end

  def test_voice_channel_id_of_a_user
    server = FakeVoiceServer.new({ 7 => FakeVoiceState.new(FakeVoiceChannel.new(33)), 8 => FakeVoiceState.new(nil) })
    assert_equal 33, music_voice_channel_id(server, 7)
    assert_nil music_voice_channel_id(server, 8)
    assert_nil music_voice_channel_id(server, 9)
  end
end
