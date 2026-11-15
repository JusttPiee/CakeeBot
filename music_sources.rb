# Finds songs for voice music: a search text or a link becomes a list of MusicTrack.
# YouTube and SoundCloud go through yt-dlp. Spotify links are handed to spotify_embed.rb.
# yt-dlp is run through a "runner" so tests can fake it (see YT_DLP_RUNNER).
require 'json'
require 'uri'
require 'open3'
require_relative './config'
require_relative './music_queue'
require_relative './spotify_embed'

# tracks: the songs found. error: a short message for the user, or nil.
# cut_off: true when a playlist had more than MUSIC_PLAYLIST_LIMIT songs.
MusicFindResult = Struct.new(:tracks, :error, :cut_off, keyword_init: true)

YT_DLP_EXTRA_ARGS = ['--js-runtimes', 'node', '--no-warnings'].freeze
YOUTUBE_HOSTS = %w[youtube.com www.youtube.com m.youtube.com music.youtube.com youtu.be].freeze
SOUNDCLOUD_HOSTS = %w[soundcloud.com www.soundcloud.com m.soundcloud.com].freeze

# The full command line: yt-dlp, the arguments every call needs, then the given arguments
def yt_dlp_command(args)
  ['yt-dlp', *YT_DLP_EXTRA_ARGS, *args]
end

# Runs yt-dlp with the given arguments. Returns [output text, ok].
# Stops yt-dlp and returns ["", false] if it takes longer than MUSIC_COMMAND_TIMEOUT_SECONDS.
YT_DLP_RUNNER = lambda do |args|
  command = yt_dlp_command(args)
  Open3.popen3(*command) do |stdin, stdout, stderr, wait_thread|
    stdin.close
    run_yt_dlp_to_end(stdout, stderr, wait_thread)
  end
rescue StandardError => e
  log "🎵 yt-dlp could not run (#{e.class})"
  ['', false]
end

# Waits for a running yt-dlp. Returns [output text, ok] and logs one line when it failed or took too long.
# The output and the error text are each read in their own thread: if nobody read one of them,
# yt-dlp could fill that pipe and wait forever.
def run_yt_dlp_to_end(stdout, stderr, wait_thread)
  output_reader = Thread.new { stdout.read }
  error_reader = Thread.new { stderr.read }
  return yt_dlp_timed_out(wait_thread, output_reader, error_reader) unless wait_thread.join(MUSIC_COMMAND_TIMEOUT_SECONDS)

  ok = wait_thread.value.success?
  log "🎵 yt-dlp failed: #{yt_dlp_error_line(error_reader.value)}" unless ok
  [output_reader.value, ok]
end

# yt-dlp took too long: stop it and its readers, log it. Returns ["", false]
def yt_dlp_timed_out(wait_thread, output_reader, error_reader)
  Process.kill('KILL', wait_thread.pid) rescue nil
  output_reader.kill
  error_reader.kill
  log "🎵 yt-dlp timed out after #{MUSIC_COMMAND_TIMEOUT_SECONDS} s"
  ['', false]
end

# The last line yt-dlp wrote to its error output (usually the "ERROR: ..." line), kept short
def yt_dlp_error_line(text)
  line = text.to_s.lines.map(&:strip).reject(&:empty?).last
  line ? line[0, 300] : 'no error text'
end

# --- what kind of link is it ---

# Says what the text is: :search, :youtube_video, :youtube_playlist, :soundcloud_track,
# :soundcloud_set, :spotify or :unsupported
def music_link_kind(text)
  return :search unless text.strip.start_with?('http')

  uri = parse_music_uri(text.strip)
  return :unsupported if uri.nil? || uri.host.nil?

  host = uri.host.downcase
  return youtube_link_kind(uri) if YOUTUBE_HOSTS.include?(host)
  return soundcloud_link_kind(uri) if SOUNDCLOUD_HOSTS.include?(host)
  return :spotify if host == 'open.spotify.com'

  :unsupported
end

# URI.parse that gives nil instead of an error for broken links
def parse_music_uri(text)
  URI.parse(text)
rescue URI::InvalidURIError
  nil
end

# Only youtube.com/playlist?list= is a playlist. Everything else on YouTube is one video
def youtube_link_kind(uri)
  is_playlist = uri.path == '/playlist' && uri.query.to_s.include?('list=')
  is_playlist ? :youtube_playlist : :youtube_video
end

# A SoundCloud link with /sets/ in it is a playlist, otherwise one track
def soundcloud_link_kind(uri)
  uri.path.include?('/sets/') ? :soundcloud_set : :soundcloud_track
end

# Removes list, index and start_radio from a watch?v= link, so only that one song is played
def youtube_single_url(url)
  uri = parse_music_uri(url)
  return url if uri.nil? || uri.query.nil?

  kept = URI.decode_www_form(uri.query).reject { |name, _| %w[list index start_radio].include?(name) }
  uri.query = kept.empty? ? nil : URI.encode_www_form(kept)
  uri.to_s
end

# --- finding songs ---

# Turns a search text or link into songs. Never raises: problems come back in result.error
def find_music(text, requester_id, runner: YT_DLP_RUNNER, spotify_reader: ->(spotify_text, id) { find_spotify_music(spotify_text, id) })
  text = text.strip
  case music_link_kind(text)
  when :search then find_one_song("ytsearch1:#{text}", requester_id, runner)
  when :youtube_video then find_one_song(youtube_single_url(text), requester_id, runner)
  when :soundcloud_track then find_one_song(text, requester_id, runner)
  when :youtube_playlist, :soundcloud_set then find_playlist(text, requester_id, runner)
  when :spotify then spotify_reader.call(text, requester_id)
  else music_error('That link is not supported. Use a YouTube, SoundCloud or Spotify link, or type a song name.')
  end
rescue StandardError => e
  log "🎵 finding music failed (#{e.class})"
  music_error('Something went wrong while looking for that song.')
end

# A result with no songs and a message for the user
def music_error(message)
  MusicFindResult.new(tracks: [], error: message, cut_off: false)
end

# Asks yt-dlp for one song (a link or a ytsearch1: text)
def find_one_song(target, requester_id, runner)
  output, ok = runner.call(['--dump-json', '--no-playlist', target])
  track = ok ? first_track_in(output, requester_id) : nil
  return music_error('I could not find that song.') if track.nil?

  MusicFindResult.new(tracks: [track], error: nil, cut_off: false)
end

# Asks yt-dlp for the songs of a playlist, one more than the limit so we can tell it was cut
def find_playlist(url, requester_id, runner)
  output, ok = runner.call(['--flat-playlist', '--dump-json', '--playlist-end', (MUSIC_PLAYLIST_LIMIT + 1).to_s, url])
  tracks = ok ? tracks_in(output, requester_id) : []
  return music_error('I could not read that playlist.') if tracks.empty?

  MusicFindResult.new(tracks: tracks.first(MUSIC_PLAYLIST_LIMIT), error: nil, cut_off: tracks.length > MUSIC_PLAYLIST_LIMIT)
end

# Fills the url, duration and thumbnail of a track that only has a search text.
# Keeps the title, artist, playlist and requester. Returns nil if YouTube has no result
def resolve_search_track(track, runner: YT_DLP_RUNNER)
  output, ok = runner.call(['--dump-json', '--no-playlist', "ytsearch1:#{track.search}"])
  found = ok ? first_track_in(output, track.requester_id) : nil
  return nil if found.nil? || found.url.nil?

  copy = track.dup
  copy.url = found.url
  copy.duration = found.duration
  copy.thumbnail = found.thumbnail
  copy
end

# --- reading yt-dlp output ---

# One MusicTrack per JSON line. Lines that are not valid JSON are skipped
def tracks_in(output, requester_id)
  output.each_line.filter_map do |line|
    data = parse_json_line(line)
    data && track_from_json(data, requester_id)
  end
end

# The first song in yt-dlp output, or nil
def first_track_in(output, requester_id)
  tracks_in(output, requester_id).first
end

# A parsed JSON hash, or nil if the line is empty or broken
def parse_json_line(line)
  return nil if line.strip.empty?

  data = JSON.parse(line)
  data.is_a?(Hash) ? data : nil
rescue JSON::ParserError
  nil
end

# Builds a MusicTrack from one yt-dlp JSON object
def track_from_json(data, requester_id)
  MusicTrack.new(
    title: data['title'],
    artist: data['uploader'] || data['channel'],
    duration: data['duration']&.to_i,
    thumbnail: data['thumbnail'] || data['thumbnails']&.last&.fetch('url', nil),
    url: data['webpage_url'] || data['url'],
    requester_id: requester_id,
    playlist_id: data['playlist_id'],
    playlist_name: data['playlist_title']
  )
end
