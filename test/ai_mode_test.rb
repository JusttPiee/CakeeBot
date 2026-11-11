require_relative "test_helper"
require_relative "../ai_mode"

class AiModeTest < Minitest::Test
  FakeChannel = Struct.new(:id)

  def setup
    @path = File.join(Dir.mktmpdir("cake-ai-mode"), "ai_config.txt")
    @histories = {}
    @channel = FakeChannel.new(900)
  end

  def test_on_saves_the_channel_and_loads_its_history
    loader = ->(_bot, _channel) { [:loaded] }
    assert_equal true, turn_ai_mode_on(:bot, @histories, @path, @channel, loader)
    assert_equal ["900"], load_ai_channels(@path)
    assert_equal [:loaded], @histories[900]
    assert_equal false, turn_ai_mode_on(:bot, @histories, @path, @channel, loader) # already on
  end

  def test_off_forgets_the_history
    turn_ai_mode_on(:bot, @histories, @path, @channel, ->(_bot, _channel) { [:loaded] })
    assert_equal true, turn_ai_mode_off(@histories, @path, 900)
    assert_empty load_ai_channels(@path)
    refute @histories.key?(900)
    assert_equal false, turn_ai_mode_off(@histories, @path, 900)
  end
end
