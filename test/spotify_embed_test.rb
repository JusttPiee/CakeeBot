require_relative "test_helper"
require_relative "../spotify_embed"

class SpotifyEmbedTest < Minitest::Test
  def fixture(name)
    File.read(File.join(__dir__, "fixtures", "music", name))
  end

  def test_spotify_link_parts
    assert_equal({ type: "playlist", id: "37i9" }, spotify_link("https://open.spotify.com/intl-vi/playlist/37i9?si=abc"))
    assert_nil spotify_link("https://youtu.be/x")
  end

  def test_embed_url
    assert_equal "https://open.spotify.com/embed/album/A1", spotify_embed_url({ type: "album", id: "A1" })
  end

  def test_entity_from_html
    entity = spotify_entity_from_html(fixture("spotify_track.html"))
    assert_equal "track", entity["type"]
    assert_nil spotify_entity_from_html("<html></html>")
  end

  def test_track_becomes_pending_search
    result = find_spotify_music("https://open.spotify.com/track/1", 5, fetcher: ->(_) { fixture("spotify_track.html") })
    track = result.tracks.first
    assert_nil track.url
    assert_equal "Rick Astley", track.artist
    assert_equal 5, track.requester_id
    assert_includes track.search, track.title
  end

  def test_playlist_tracks_share_playlist_id
    result = find_spotify_music("https://open.spotify.com/playlist/P", 5, fetcher: ->(_) { fixture("spotify_playlist.html") })
    assert result.tracks.length > 1
    assert_equal ["spotify:P"], result.tracks.map(&:playlist_id).uniq
    assert_equal "Today’s Top Hits", result.tracks.first.playlist_name
    assert_equal 225, result.tracks.first.duration
    assert_equal false, result.cut_off
  end

  def test_playlist_is_cut_at_limit
    stub_limit = 2
    result = nil
    with_playlist_limit(stub_limit) do
      result = find_spotify_music("https://open.spotify.com/playlist/P", 5, fetcher: ->(_) { fixture("spotify_playlist.html") })
    end
    assert_equal 2, result.tracks.length
    assert result.cut_off
  end

  def test_page_without_data_gives_error
    result = find_spotify_music("https://open.spotify.com/track/1", 5, fetcher: ->(_) { "<html></html>" })
    assert_empty result.tracks
    assert_equal "❗ Could not read this Spotify link.", result.error
  end

  def test_fetch_error_gives_error
    result = find_spotify_music("https://open.spotify.com/track/1", 5, fetcher: ->(_) { raise "HTTP 429" })
    assert_equal "❗ Could not read this Spotify link.", result.error
  end

  private

  def with_playlist_limit(value)
    old = MUSIC_PLAYLIST_LIMIT
    Object.send(:remove_const, :MUSIC_PLAYLIST_LIMIT)
    Object.const_set(:MUSIC_PLAYLIST_LIMIT, value)
    yield
  ensure
    Object.send(:remove_const, :MUSIC_PLAYLIST_LIMIT)
    Object.const_set(:MUSIC_PLAYLIST_LIMIT, old)
  end
end
