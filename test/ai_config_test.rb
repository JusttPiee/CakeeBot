require_relative "test_helper"
require "tmpdir"
require_relative "../ai_config"

# Saving the AI channels (one ID per line). Every test uses its own temporary file.
class AiConfigTest < Minitest::Test
  def with_config_file
    Dir.mktmpdir { |dir| yield File.join(dir, "ai_config.txt") }
  end

  def test_no_file_means_no_ai_channels
    with_config_file { |path| assert_equal [], load_ai_channels(path) }
  end

  def test_several_channels_can_be_on_at_once
    with_config_file do |path|
      add_ai_channel(path, 555)
      add_ai_channel(path, 777)
      assert_equal %w[555 777], load_ai_channels(path)
      assert ai_channel?(path, 555)
      assert ai_channel?(path, 777)
    end
  end

  def test_adding_the_same_channel_twice_saves_it_once
    with_config_file do |path|
      assert add_ai_channel(path, 555)
      refute add_ai_channel(path, 555)
      assert_equal ["555"], load_ai_channels(path)
    end
  end

  def test_turning_off_one_channel_keeps_the_others
    with_config_file do |path|
      add_ai_channel(path, 555)
      add_ai_channel(path, 777)
      assert remove_ai_channel(path, 555)
      assert_equal ["777"], load_ai_channels(path)
    end
  end

  def test_turning_off_a_channel_that_was_not_on
    with_config_file { |path| refute remove_ai_channel(path, 555) }
  end

  def test_old_file_with_one_id_still_works
    with_config_file do |path|
      File.write(path, "1382043745305755748\n")
      assert ai_channel?(path, 1382043745305755748)
    end
  end
end
