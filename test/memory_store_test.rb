require_relative "test_helper"
require_relative "../config"
require_relative "../memory_store"

# Reading and writing memory files safely, one folder per server.
class MemoryStoreTest < Minitest::Test
  def setup
    clear_test_memory
  end

  def test_rejects_unsafe_paths
    ["../x.md", "events/../../x.md", "/etc/passwd", "C:/Windows/x.md", "events/a.txt", "", 'events\..\..\x.md'].each do |path|
      assert_nil resolve_memory_path(1, path), path
    end
  end

  def test_accepts_paths_inside_the_server_folder
    assert_equal File.expand_path(File.join(MEMORY_DIR, "1", "events", "a.md")), resolve_memory_path(1, "events/a.md")
  end

  def test_write_then_read
    write_memory_file(1, "users/5.md", "hello")
    assert_equal "hello", read_memory_file(1, "users/5.md")
  end

  def test_missing_file_reads_as_nil
    assert_nil read_memory_file(1, "users/5.md")
  end

  def test_servers_are_separate
    write_memory_file(1, "users/5.md", "server one")
    assert_nil read_memory_file(2, "users/5.md")
  end

  def test_writing_an_unsafe_path_raises
    assert_raises(ArgumentError) { write_memory_file(1, "../evil.md", "x") }
  end

  def test_list_files_in_a_folder
    write_memory_file(1, "events/b.md", "x")
    write_memory_file(1, "events/a.md", "x")
    assert_equal ["events/a.md", "events/b.md"], list_memory_files(1, "events")
    assert_equal [], list_memory_files(1, "users")
  end

  def test_delete_a_file
    write_memory_file(1, "events/a.md", "x")
    delete_memory_file(1, "events/a.md")
    assert_nil read_memory_file(1, "events/a.md")
  end

  def test_server_lock_runs_the_block
    assert_equal 42, with_server_memory_lock(1) { 42 }
  end

  def test_badly_encoded_file_is_still_readable
    path = File.join(MEMORY_DIR, "1", "events", "x.md")
    FileUtils.mkdir_p(File.dirname(path))
    File.binwrite(path, "title: Gi\xE1i \xF0\xE2u\nwhen: 2099-01-01\n\nx".b) # an old Windows encoding, not UTF-8
    assert read_memory_file(1, "events/x.md").valid_encoding?
  end
end
