# The list of songs for voice music: the song playing now and the songs waiting.
# Plain data, no Discord and no threads. The music controller owns one of these per server.

# One song. `duration` is in seconds or nil.
# `url` is the page to play; when it is nil, `search` ("title artist") still has to be looked up on YouTube.
MusicTrack = Struct.new(
  :title, :artist, :duration, :thumbnail, :url, :search,
  :requester_id, :playlist_id, :playlist_name,
  keyword_init: true
)

class MusicQueue
  attr_reader :current
  attr_accessor :paused

  def initialize
    reset!
  end

  # Adds songs at the end of the waiting list. Returns how many were added
  def add(tracks)
    @waiting.concat(tracks)
    tracks.length
  end

  # Moves on: the first waiting song becomes current (or nil if none is waiting). Returns it
  def advance!
    @current = @waiting.shift
  end

  # Removes the waiting songs from the same playlist as the current song. Returns how many.
  # 0 if the current song is not from a playlist
  def skip_playlist!
    return 0 if @current.nil? || @current.playlist_id.nil?

    before = @waiting.length
    @waiting.reject! { |track| track.playlist_id == @current.playlist_id }
    before - @waiting.length
  end

  # Removes all waiting songs but keeps the current one. Returns how many were removed
  def clear!
    removed = @waiting.length
    @waiting.clear
    removed
  end

  # Back to the start: no current song, nothing waiting, not paused
  def reset!
    @current = nil
    @waiting = []
    @paused = false
  end

  # The waiting songs, as a copy so callers cannot change the real list
  def waiting
    @waiting.dup
  end

  # How many songs are waiting
  def size
    @waiting.length
  end
end
