require_relative "test_helper"
require_relative "../data_paths"

class DataPathsTest < Minitest::Test
  def test_default_is_the_project_folder
    assert_equal File.expand_path("..", __dir__), data_dir_from({})
    assert_equal File.expand_path("..", __dir__), data_dir_from({ "CAKE_DATA_DIR" => " " })
  end

  def test_the_variable_moves_the_folder
    Dir.mktmpdir { |dir| assert_equal File.expand_path(dir), data_dir_from({ "CAKE_DATA_DIR" => dir }) }
  end

  def test_knows_if_the_folder_was_moved
    refute data_dir_set?({})
    refute data_dir_set?({ "CAKE_DATA_DIR" => "" })
    assert data_dir_set?({ "CAKE_DATA_DIR" => "/data" })
  end

  def test_personality_moves_only_with_the_data_folder
    assert_equal File.expand_path("../prompts/personality.txt", __dir__), personality_path(nil)
    assert_equal "/data/personality.txt", personality_path("/data")
  end

  def test_seed_copies_once_and_never_overwrites
    Dir.mktmpdir do |source|
      Dir.mktmpdir do |dir|
        File.write(File.join(source, "badwords.txt"), "one")
        seed_data_file("badwords.txt", dir, source)
        assert_equal "one", File.read(File.join(dir, "badwords.txt"))
        File.write(File.join(dir, "badwords.txt"), "mine")
        seed_data_file("badwords.txt", dir, source)
        assert_equal "mine", File.read(File.join(dir, "badwords.txt"))
      end
    end
  end
end
