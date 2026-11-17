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

  # A queue playing "a" with "b" and "c" waiting, in this loop mode
  def looping(mode)
    queue = MusicQueue.new
    queue.add([track("a"), track("b"), track("c")])
    queue.advance!
    queue.loop_mode = mode
    queue
  end

  def test_loop_starts_off_and_cycles
    queue = MusicQueue.new
    assert_equal :off, queue.loop_mode
    assert_equal %i[song queue off], 3.times.map { queue.cycle_loop! }
  end

  def test_loop_off_moves_on_and_forgets
    queue = looping(:off)
    assert_equal "b", queue.advance!(:finished).title
    assert_equal ["c"], queue.waiting.map(&:title)
  end

  def test_loop_song_repeats_a_finished_song_but_not_a_skipped_one
    queue = looping(:song)
    assert_equal "a", queue.advance!(:finished).title
    assert_equal "b", queue.advance!(:skipped).title
    assert_equal ["c"], queue.waiting.map(&:title)
  end

  def test_loop_queue_puts_finished_and_skipped_songs_at_the_end
    queue = looping(:queue)
    assert_equal "b", queue.advance!(:finished).title
    assert_equal "c", queue.advance!(:skipped).title
    assert_equal %w[a b], queue.waiting.map(&:title)
  end

  def test_loop_queue_with_one_song_plays_it_again
    queue = MusicQueue.new
    queue.add([track("a")])
    queue.advance!
    queue.loop_mode = :queue
    assert_equal "a", queue.advance!(:finished).title
  end

  # A broken song must never loop forever
  def test_failed_songs_are_never_repeated
    %i[song queue].each do |mode|
      queue = looping(mode)
      assert_equal "b", queue.advance!(:failed).title, mode
      assert_equal ["c"], queue.waiting.map(&:title), mode
    end
  end

  def test_skip_playlist_does_not_bring_the_song_back_in_loop_queue
    queue = MusicQueue.new
    queue.add([track("p1", "P"), track("p2", "P"), track("solo")])
    queue.advance!
    queue.loop_mode = :queue
    queue.skip_playlist!
    assert_equal "solo", queue.advance!(:skipped).title
    assert_empty queue.waiting
  end

  def test_reset_turns_loop_off
    queue = looping(:queue)
    queue.reset!
    assert_equal :off, queue.loop_mode
  end

  def test_shuffle_mixes_waiting_songs_and_keeps_current
    queue = MusicQueue.new
    queue.add(%w[a b c d e f].map { |title| track(title) })
    queue.advance! # a playing
    assert_equal 5, queue.shuffle!(Random.new(1))
    assert_equal "a", queue.current.title
    assert_equal %w[b c d e f], queue.waiting.map(&:title).sort
    refute_equal %w[b c d e f], queue.waiting.map(&:title)
  end

  def test_shuffle_needs_two_waiting_songs
    queue = MusicQueue.new
    queue.add([track("a"), track("b")])
    queue.advance!
    assert_equal 0, queue.shuffle!
    assert_equal ["b"], queue.waiting.map(&:title)
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
