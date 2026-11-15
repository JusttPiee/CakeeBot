require_relative "test_helper"
require_relative "../music_queue"

class MusicQueueTest < Minitest::Test
  # A small song for tests, optionally part of a playlist
  def track(title, playlist = nil)
    MusicTrack.new(title: title, url: "u/#{title}", playlist_id: playlist, playlist_name: playlist)
  end

  def test_add_then_advance_plays_in_order
    queue = MusicQueue.new
    assert_equal 2, queue.add([track("a"), track("b")])
    assert_equal "a", queue.advance!.title
    assert_equal "b", queue.advance!.title
    assert_nil queue.advance!
  end

  def test_skip_playlist_keeps_other_songs
    queue = MusicQueue.new
    queue.add([track("p1", "P"), track("p2", "P"), track("solo"), track("p3", "P")])
    queue.advance! # p1 playing
    assert_equal 2, queue.skip_playlist! # p2 and p3 removed
    assert_equal ["solo"], queue.waiting.map(&:title)
  end

  def test_skip_playlist_without_playlist_removes_nothing
    queue = MusicQueue.new
    queue.add([track("a"), track("b")])
    queue.advance!
    assert_equal 0, queue.skip_playlist!
    assert_equal 1, queue.size
  end

  def test_clear_keeps_current
    queue = MusicQueue.new
    queue.add([track("a"), track("b"), track("c")])
    queue.advance!
    assert_equal 2, queue.clear!
    assert_equal "a", queue.current.title
    assert_equal 0, queue.size
  end

  def test_waiting_is_a_copy
    queue = MusicQueue.new
    queue.add([track("a")])
    queue.waiting.clear
    assert_equal 1, queue.size
  end

  def test_reset_empties_everything
    queue = MusicQueue.new
    queue.add([track("a"), track("b")])
    queue.advance!
    queue.paused = true
    queue.reset!
    assert_nil queue.current
    assert_equal 0, queue.size
    assert_equal false, queue.paused
  end
end
