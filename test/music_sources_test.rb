require_relative "test_helper"
require "stringio"
require_relative "../music_sources"

# Pretends to be yt-dlp: returns the given text and remembers the arguments it was called with.
class FakeRunner
  attr_reader :calls

  def initialize(output, ok: true)
    @output = output
    @ok = ok
    @calls = []
  end

  def call(args)
    @calls << args
    [@output, @ok]
  end
end

class MusicSourcesTest < Minitest::Test
  def fixture(name)
    File.read(File.join(__dir__, "fixtures", "music", name))
  end

  def test_link_kinds
    assert_equal :search, music_link_kind("lạc trôi sơn tùng")
    assert_equal :youtube_video, music_link_kind("https://youtu.be/abc")
    assert_equal :youtube_video, music_link_kind("https://www.youtube.com/watch?v=abc&list=RDabc")
    assert_equal :youtube_video, music_link_kind("https://music.youtube.com/watch?v=abc")
    assert_equal :youtube_video, music_link_kind("https://m.youtube.com/shorts/abc")
    assert_equal :youtube_playlist, music_link_kind("https://www.youtube.com/playlist?list=PL1")
    assert_equal :soundcloud_set, music_link_kind("https://soundcloud.com/a/sets/b")
    assert_equal :soundcloud_track, music_link_kind("https://soundcloud.com/a/b")
    assert_equal :spotify, music_link_kind("https://open.spotify.com/intl-vi/track/123?si=x")
    assert_equal :unsupported, music_link_kind("https://example.com/song.mp3")
  end

  def test_mix_link_plays_one_song
    assert_equal "https://www.youtube.com/watch?v=abc", youtube_single_url("https://www.youtube.com/watch?v=abc&list=RDabc&start_radio=1")
  end

  def test_search_uses_first_youtube_result
    runner = FakeRunner.new(fixture("yt_video.json"))
    result = find_music("never gonna", 42, runner: runner)
    assert_includes runner.calls.first, "ytsearch1:never gonna"
    assert_equal 42, result.tracks.first.requester_id
    refute_nil result.tracks.first.url
    assert_equal "Rick Astley", result.tracks.first.artist
    assert_equal 213, result.tracks.first.duration
  end

  def test_playlist_fixture_fields
    result = find_music("https://www.youtube.com/playlist?list=PL123", 5, runner: FakeRunner.new(fixture("yt_playlist.jsonl")))
    assert_equal 2, result.tracks.length
    refute result.cut_off
    first = result.tracks.first
    assert_equal "Some Channel", first.artist
    assert_equal "https://i.ytimg.com/vi/aaa/hqdefault.jpg", first.thumbnail
    assert_equal "PL123", first.playlist_id
  end

  def test_playlist_over_limit_is_cut_off
    lines = (1..(MUSIC_PLAYLIST_LIMIT + 1)).map { |i| { "title" => "s#{i}", "url" => "u#{i}", "playlist_id" => "PL", "playlist_title" => "Mix" }.to_json }
    result = find_music("https://www.youtube.com/playlist?list=PL", 1, runner: FakeRunner.new(lines.join("\n")))
    assert_equal MUSIC_PLAYLIST_LIMIT, result.tracks.length
    assert result.cut_off
    assert_equal "Mix", result.tracks.first.playlist_name
  end

  def test_failed_run_gives_error
    result = find_music("https://youtu.be/x", 1, runner: FakeRunner.new("", ok: false))
    assert_empty result.tracks
    refute_nil result.error
  end

  def test_bad_json_line_is_skipped
    result = find_music("https://www.youtube.com/playlist?list=PL", 1, runner: FakeRunner.new("{\"title\":\"a\",\"url\":\"u\"}\nnot json"))
    assert_equal 1, result.tracks.length
  end

  def test_unsupported_link_runs_nothing
    runner = FakeRunner.new("")
    result = find_music("https://example.com/x.mp3", 1, runner: runner)
    assert_empty runner.calls
    refute_nil result.error
  end

  def test_spotify_link_goes_to_spotify_reader
    seen = nil
    reader = ->(text, id) { seen = [text, id]; MusicFindResult.new(tracks: [], error: nil, cut_off: false) }
    find_music("https://open.spotify.com/track/1", 9, runner: FakeRunner.new(""), spotify_reader: reader)
    assert_equal ["https://open.spotify.com/track/1", 9], seen
  end

  def test_search_call_shape
    runner = FakeRunner.new(fixture("yt_video.json"))
    find_music("never gonna", 1, runner: runner)
    assert_equal [["--dump-json", "--no-playlist", "ytsearch1:never gonna"]], runner.calls
  end

  def test_youtube_playlist_call_shape
    url = "https://www.youtube.com/playlist?list=PL123"
    runner = FakeRunner.new(fixture("yt_playlist.jsonl"))
    find_music(url, 1, runner: runner)
    assert_equal [["--flat-playlist", "--dump-json", "--playlist-end", "#{MUSIC_PLAYLIST_LIMIT + 1}", url]], runner.calls
  end

  def test_soundcloud_set_call_shape
    url = "https://soundcloud.com/a/sets/b"
    runner = FakeRunner.new(fixture("yt_playlist.jsonl"))
    find_music(url, 1, runner: runner)
    assert_equal [["--flat-playlist", "--dump-json", "--playlist-end", "#{MUSIC_PLAYLIST_LIMIT + 1}", url]], runner.calls
  end

  def test_soundcloud_track_call_shape
    url = "https://soundcloud.com/a/b"
    runner = FakeRunner.new(fixture("yt_video.json"))
    find_music(url, 1, runner: runner)
    assert_equal [["--dump-json", "--no-playlist", url]], runner.calls
  end

  def test_resolve_search_call_shape
    runner = FakeRunner.new(fixture("yt_video.json"))
    resolve_search_track(MusicTrack.new(title: "S", search: "S Singer"), runner: runner)
    assert_equal [["--dump-json", "--no-playlist", "ytsearch1:S Singer"]], runner.calls
  end

  def test_yt_dlp_command_adds_extra_args
    assert_equal ["yt-dlp", "--js-runtimes", "node", "--no-warnings", "--dump-json", "x"], yt_dlp_command(["--dump-json", "x"])
  end

  def test_mix_link_is_cleaned_before_running
    runner = FakeRunner.new(fixture("yt_video.json"))
    find_music("https://www.youtube.com/watch?v=abc&list=RDabc", 1, runner: runner)
    assert_includes runner.calls.first, "https://www.youtube.com/watch?v=abc"
  end

  def test_resolve_search_track_fills_url_and_keeps_playlist
    pending = MusicTrack.new(title: "Song", artist: "Singer", search: "Song Singer", playlist_id: "S1", playlist_name: "Album", requester_id: 7)
    found = resolve_search_track(pending, runner: FakeRunner.new(fixture("yt_video.json")))
    refute_nil found.url
    assert_equal "Song", found.title
    assert_equal "S1", found.playlist_id
    assert_equal 7, found.requester_id
  end

  def test_resolve_search_track_returns_nil_when_failed
    pending = MusicTrack.new(title: "Song", search: "Song")
    assert_nil resolve_search_track(pending, runner: FakeRunner.new("", ok: false))
  end

  # --- running yt-dlp: why it failed goes to the log ---

  # Pretends to be the thread Open3 gives back: finished (with an exit status) or still running
  FakeExit = Struct.new(:ok) { def success? = ok }
  class FakeWait
    def initialize(ok, finished: true)
      @ok = ok
      @finished = finished
    end

    def join(_seconds) = @finished ? self : nil
    def value = FakeExit.new(@ok)
    def pid = 999_999_999
  end

  def test_yt_dlp_error_is_logged_with_its_last_line
    LOGS.clear
    errors = StringIO.new("WARNING: something\nERROR: [youtube] abc: Sign in to confirm you're not a bot\n\n")
    output, ok = run_yt_dlp_to_end(StringIO.new(""), errors, FakeWait.new(false))
    refute ok
    assert_equal "", output
    assert_includes LOGS, "🎵 yt-dlp failed: ERROR: [youtube] abc: Sign in to confirm you're not a bot"
  end

  def test_yt_dlp_success_returns_output_and_logs_nothing
    LOGS.clear
    output, ok = run_yt_dlp_to_end(StringIO.new("{}\n"), StringIO.new("WARNING: x\n"), FakeWait.new(true))
    assert ok
    assert_equal "{}\n", output
    assert_empty LOGS
  end

  def test_yt_dlp_timeout_is_logged
    LOGS.clear
    output, ok = run_yt_dlp_to_end(StringIO.new(""), StringIO.new(""), FakeWait.new(false, finished: false))
    assert_equal ["", false], [output, ok]
    assert_includes LOGS, "🎵 yt-dlp timed out after #{MUSIC_COMMAND_TIMEOUT_SECONDS} s"
  end

  def test_yt_dlp_error_without_text
    assert_equal "no error text", yt_dlp_error_line(" \n")
  end
end
