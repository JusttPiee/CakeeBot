# Reads Spotify links without a key: the public embed page of a track, album or playlist
# holds the song list as JSON, which becomes a list of MusicTrack.
# Spotify gives no audio, so every track only gets a search text; YouTube is searched later.
# The page is fetched through a "fetcher" so tests can fake it (see SPOTIFY_FETCHER).
require 'json'
require 'net/http'
require 'uri'
require_relative './config'
require_relative './music_queue'
require_relative './music_sources'

SPOTIFY_ERROR = '❗ Could not read this Spotify link.'.freeze
SPOTIFY_TYPES = %w[track album playlist].freeze
SPOTIFY_USER_AGENT = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36'.freeze

# Downloads a page and returns its HTML. Raises if Spotify does not answer 200.
SPOTIFY_FETCHER = lambda do |url|
  uri = URI.parse(url)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.open_timeout = 10
  http.read_timeout = 10
  response = http.get(uri.request_uri, 'User-Agent' => SPOTIFY_USER_AGENT)
  raise "HTTP #{response.code}" unless response.code == '200'

  response.body.to_s.dup.force_encoding('UTF-8')
end

# --- the link ---

# Gives { type:, id: } for a Spotify track, album or playlist link, or nil.
# A language part like intl-vi/ and a query like ?si=... are ignored.
def spotify_link(text)
  uri = URI.parse(text.to_s.strip)
  return nil unless uri.host == 'open.spotify.com'

  parts = uri.path.split('/').reject(&:empty?)
  parts.shift if parts.first.to_s.start_with?('intl-')
  type, id = parts
  return nil unless SPOTIFY_TYPES.include?(type) && id

  { type: type, id: id }
rescue URI::InvalidURIError
  nil
end

# The address of the embed page for a link made by spotify_link
def spotify_embed_url(link)
  "https://open.spotify.com/embed/#{link[:type]}/#{link[:id]}"
end

# --- reading the page ---

# Finds the JSON in the page and returns props.pageProps.state.data.entity, or nil.
# This path was checked against a real embed page (track and playlist) on 2026-11-16.
def spotify_entity_from_html(html)
  match = html.match(%r{<script id="__NEXT_DATA__"[^>]*>(.*?)</script>}m)
  return nil if match.nil?

  data = JSON.parse(match[1])
  entity = data.dig('props', 'pageProps', 'state', 'data', 'entity')
  entity.is_a?(Hash) ? entity : nil
rescue JSON::ParserError
  nil
end

# --- making songs ---

# Turns a Spotify link into songs. Never raises: problems come back in result.error
def find_spotify_music(text, requester_id, fetcher: SPOTIFY_FETCHER)
  link = spotify_link(text)
  raise 'not a Spotify link' if link.nil?

  entity = spotify_entity_from_html(fetcher.call(spotify_embed_url(link)))
  raise 'no song data in the page' if entity.nil?

  if link[:type] == 'track'
    single_spotify_result(entity, requester_id)
  else
    list_spotify_result(entity, link, requester_id)
  end
rescue StandardError => e
  log "🎵 Spotify read failed: #{e.message}"
  music_error(SPOTIFY_ERROR)
end

# The result for one track link
def single_spotify_result(entity, requester_id)
  artist = entity['artists'].to_a.map { |a| a['name'] }.join(', ')
  track = pending_spotify_track(entity['title'] || entity['name'], artist, nil, requester_id)
  MusicFindResult.new(tracks: [track], error: nil, cut_off: false)
end

# The result for an album or playlist link, cut at MUSIC_PLAYLIST_LIMIT songs
def list_spotify_result(entity, link, requester_id)
  entries = entity['trackList'].to_a
  raise 'no songs in the list' if entries.empty?

  tracks = entries.first(MUSIC_PLAYLIST_LIMIT).map do |entry|
    track = pending_spotify_track(entry['title'], entry['subtitle'], entry['duration'], requester_id)
    track.playlist_id = "spotify:#{link[:id]}"
    track.playlist_name = entity['name'] || entity['title']
    track
  end
  MusicFindResult.new(tracks: tracks, error: nil, cut_off: entries.length > MUSIC_PLAYLIST_LIMIT)
end

# A track with no url yet, only a search text for YouTube. duration_ms may be nil
def pending_spotify_track(title, artist, duration_ms, requester_id)
  MusicTrack.new(
    title: title,
    artist: artist,
    duration: duration_ms && (duration_ms / 1000),
    url: nil,
    search: "#{title} #{artist}".strip,
    requester_id: requester_id
  )
end
