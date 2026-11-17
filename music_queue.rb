# The list of songs for voice music: the song playing now and the songs waiting.
# Plain data, no Discord and no threads. The music controller owns one of these per server.

# One song. `duration` is in seconds or nil.
# `url` is the page to play; when it is nil, `search` ("title artist") still has to be looked up on YouTube.
MusicTrack = Struct.new(
  :title, :artist, :duration, :thumbnail, :url, :search,
  :requester_id, :playlist_id, :playlist_name,
  keyword_init: true
)

# The loop modes, in the order !loop and the Loop button go through them
MUSIC_LOOP_MODES = %i[off song queue].freeze

class MusicQueue
  attr_reader :current
  attr_accessor :paused
  attr_accessor :loop_mode # :off, :song (repeat the current song) or :queue (finished songs go to the end)

  def initialize
    reset!
  end

  # Adds songs at the end of the waiting list. Returns how many were added
  def add(tracks)
    @waiting.concat(tracks)
    tracks.length
  end

  # Moves on and returns the new current song (nil when none is waiting).
  # `why` is why the current song ends, and the loop mode decides what happens to it:
  #   :finished - played to the end: loop song plays it again, loop queue puts it at the end
  #   :skipped  - someone skipped it: loop queue puts it at the end
  #   :failed   - could not be played: never repeated, so a broken song cannot loop forever
  def advance!(why = :failed)
    return @current if why == :finished && @loop_mode == :song && @current

    @waiting.push(@current) if keep_at_the_end?(why)
    @current_dropped = false
    @current = @waiting.shift
  end

  # Goes to the next loop mode (off -> song -> queue -> off). Returns the new mode
  def cycle_loop!
    @loop_mode = MUSIC_LOOP_MODES[(MUSIC_LOOP_MODES.index(@loop_mode) + 1) % MUSIC_LOOP_MODES.length]
  end

  # Removes the waiting songs from the same playlist as the current song. Returns how many.
  # 0 if the current song is not from a playlist.
  # The current song is skipped next, and loop queue must not bring it back either
  def skip_playlist!
    return 0 if @current.nil? || @current.playlist_id.nil?

    @current_dropped = true
    before = @waiting.length
    @waiting.reject! { |track| track.playlist_id == @current.playlist_id }
    before - @waiting.length
  end

  # Mixes the waiting songs into a random order; the current song is not touched.
  # Returns how many songs were mixed, 0 when fewer than 2 are waiting (nothing to mix)
  def shuffle!(random = Random)
    return 0 if @waiting.length < 2

    @waiting.shuffle!(random: random)
    @waiting.length
  end

  # Removes all waiting songs but keeps the current one. Returns how many were removed
  def clear!
    removed = @waiting.length
    @waiting.clear
    removed
  end

  # Back to the start: no current song, nothing waiting, not paused, loop off
  def reset!
    @current = nil
    @waiting = []
    @paused = false
    @loop_mode = :off
    @current_dropped = false
  end

  # The waiting songs, as a copy so callers cannot change the real list
  def waiting
    @waiting.dup
  end

  # How many songs are waiting
  def size
    @waiting.length
  end

  private

  # Loop queue keeps songs that finished or were skipped, but not failed or dropped ones
  def keep_at_the_end?(why)
    @loop_mode == :queue && @current && why != :failed && !@current_dropped
  end
end
