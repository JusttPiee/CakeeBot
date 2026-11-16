# What the music controller remembers about one server (guild).
# Plain data. Only the controller changes it, and only while it holds its lock.
require_relative './music_queue'
require_relative './config' # MUSIC_DEFAULT_VOLUME

MusicServerState = Struct.new(
  :queue,            # the MusicQueue: song playing now and songs waiting
  :voice_channel_id, # the voice channel Cake is in (or joining); nil = not in voice
  :text_channel,     # where the panel and short notes go (the channel where music started)
  :skipping,         # a "stop" was sent for the current song; its finished/failed is on the way
  :idle_token,       # the idle wait that may make Cake leave; a new wait (or a play) makes old ones do nothing
  :joined,           # Node said "joined" for the current voice channel
  :song_sent,        # "play" was sent for the current song, so Node will send exactly one finished/failed for it
  :song_number,      # goes up for every new song, so a YouTube search that ends late can see its song is gone
  :failures_in_a_row, # songs that failed one after another; a song that plays to the end sets it back to 0
  :volume            # 0-100, kept across songs, back to MUSIC_DEFAULT_VOLUME when Cake leaves voice
) do
  # A fresh server: nothing playing, not in voice
  def self.fresh
    new(MusicQueue.new, nil, nil, false, nil, false, false, 0, 0, MUSIC_DEFAULT_VOLUME)
  end

  # Back to nothing playing and not in voice. Keeps the song counter going up,
  # so searches and idle waits started before this do nothing
  def reset!
    queue.reset!
    self.voice_channel_id = nil
    self.skipping = false
    self.idle_token = nil
    self.joined = false
    self.song_sent = false
    self.song_number += 1
    self.failures_in_a_row = 0
    self.volume = MUSIC_DEFAULT_VOLUME
  end

  # In voice, or a song is current
  def active?
    !voice_channel_id.nil? || !queue.current.nil?
  end
end
