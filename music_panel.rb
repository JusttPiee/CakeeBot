# The music panel: one message per server showing what is playing, with buttons.
# Also the text for the "Queue" button. Nothing here talks to the voice side.
require 'discordrb'
require_relative './config'
require_relative './music_queue'

# 225 => "3:45", 3723 => "1:02:03", nil => "?"
def format_duration(seconds)
  return "?" if seconds.nil?
  total = seconds.to_i
  hours = total / 3600
  minutes = (total % 3600) / 60
  secs = total % 60
  return format("%d:%02d:%02d", hours, minutes, secs) if hours > 0
  format("%d:%02d", minutes, secs)
end

# Make a title safe to put inside [ ] of a Markdown link
def safe_link_text(title)
  title.to_s.tr("[]", "()")
end

# Make an address safe to put inside ( ) of a Markdown link
def safe_link_url(url)
  url.to_s.gsub("(", "%28").gsub(")", "%29")
end

# The song title, as a link when the address is known
def track_title_line(track)
  text = safe_link_text(track.title)
  return "**#{text}**" if track.url.to_s.empty?
  "**[#{text}](#{safe_link_url(track.url)})**"
end

# "Singer • 3:45"
def track_artist_line(track)
  parts = [track.artist, format_duration(track.duration)].compact.reject { |part| part.to_s.empty? }
  parts.join(" • ")
end

# All the lines of the panel text
def panel_description_lines(track, waiting_count)
  lines = [track_title_line(track), track_artist_line(track)]
  lines << "from playlist \"#{track.playlist_name}\"" if track.playlist_name
  lines << "Asked by <@#{track.requester_id}> • #{waiting_count} songs in queue"
  lines
end

# The line under the song when it loops (nothing when loop is off)
MUSIC_LOOP_LINES = { song: "🔂 Looping this song", queue: "🔁 Looping the queue" }.freeze

# The panel for the song that is playing now (or paused). volume (0-100) adds a "🔊 50%" line,
# and a loop mode other than :off adds a line saying what loops.
def music_panel_embed(track, waiting_count, paused, volume = nil, loop_mode = :off)
  embed = Discordrb::Webhooks::Embed.new
  embed.title = paused ? "⏸ Paused" : "🎵 Now playing"
  lines = panel_description_lines(track, waiting_count)
  lines << "🔊 #{volume}%" if volume
  lines << MUSIC_LOOP_LINES[loop_mode] if MUSIC_LOOP_LINES.key?(loop_mode)
  embed.description = lines.join("\n")
  embed.thumbnail = Discordrb::Webhooks::EmbedThumbnail.new(url: track.thumbnail) if track.thumbnail
  embed
end

# The panel when the music has ended
def music_stopped_embed
  embed = Discordrb::Webhooks::Embed.new
  embed.title = "⏹ Music stopped"
  embed
end

# Button emojis. Symbols that are text by default (⏸ ⏭ 🗑 ▶) carry U+FE0F to be shown as emoji:
# without it Discord may refuse the emoji, and with it the whole panel
MUSIC_EMOJI_PAUSE = "⏸\u{FE0F}"
MUSIC_EMOJI_RESUME = "▶\u{FE0F}"
MUSIC_EMOJI_SKIP = "⏭\u{FE0F}"
MUSIC_EMOJI_CLEAR = "🗑\u{FE0F}"

# The Loop button shows the mode it is in now: [label, emoji]
MUSIC_LOOP_BUTTONS = {
  off: ["Loop: Off", "➡\u{FE0F}"],
  song: ["Loop: Song", "🔂"],
  queue: ["Loop: Queue", "🔁"]
}.freeze

# The buttons under the panel: pause/resume, skip, skip playlist, queue, clear queue,
# and on a second row volume down / up, loop and shuffle (Discord allows 5 buttons per row)
def music_panel_view(paused, loop_mode = :off)
  Discordrb::Webhooks::View.new do |view|
    view.row { |row| music_playback_buttons(row, paused) }
    view.row { |row| music_extra_buttons(row, loop_mode) }
  end
end

def music_playback_buttons(row, paused)
  row.button(style: :primary, label: paused ? "Resume" : "Pause", emoji: paused ? MUSIC_EMOJI_RESUME : MUSIC_EMOJI_PAUSE,
             custom_id: "music:toggle")
  row.button(style: :secondary, label: "Skip", emoji: MUSIC_EMOJI_SKIP, custom_id: "music:skip")
  row.button(style: :secondary, label: "Skip playlist", emoji: "⏩", custom_id: "music:skipplaylist")
  row.button(style: :secondary, label: "Queue", emoji: "📜", custom_id: "music:queue")
  row.button(style: :danger, label: "Clear queue", emoji: MUSIC_EMOJI_CLEAR, custom_id: "music:clearqueue")
end

def music_extra_buttons(row, loop_mode)
  loop_label, loop_emoji = MUSIC_LOOP_BUTTONS.fetch(loop_mode)
  row.button(style: :secondary, label: "-#{MUSIC_VOLUME_STEP}%", emoji: "🔉", custom_id: "music:voldown")
  row.button(style: :secondary, label: "+#{MUSIC_VOLUME_STEP}%", emoji: "🔊", custom_id: "music:volup")
  row.button(style: :secondary, label: loop_label, emoji: loop_emoji, custom_id: "music:loop")
  row.button(style: :secondary, label: "Shuffle", emoji: "🔀", custom_id: "music:shuffle")
end

# "title (3:45)"
def queue_line(index, track)
  "#{index}. #{track.title} (#{format_duration(track.duration)})"
end

# The text for the Queue button: what plays now, then the next songs up to the limit
def music_queue_text(current, waiting, limit = MUSIC_QUEUE_SHOW)
  lines = []
  lines << "Now: #{current.title}" if current
  return (lines << "The queue is empty.").join("\n") if waiting.empty?
  waiting.first(limit).each_with_index { |track, index| lines << queue_line(index + 1, track) }
  lines << "...and #{waiting.length - limit} more" if waiting.length > limit
  lines.join("\n")
end

# Keeps one panel message per server: edits it, or sends a new one when it is gone.
# Called from background threads. Each server has its own lock, held for the whole
# show or stop (including the Discord calls), so two calls for one server never overlap
# and the panel can never be sent twice or brought back after a stop.
class MusicPanelPoster
  def initialize
    @messages = {}
    @locks = {}
    @locks_guard = Mutex.new
  end

  # Show the panel: edit the old message, or send a new one when there is none or it was deleted
  def show(guild_id, channel, embed, view)
    lock_for(guild_id).synchronize do
      old = @messages[guild_id]
      next if old && edit_message(old, embed, view)
      @messages[guild_id] = channel.send_message("", false, embed, nil, nil, nil, view)
    end
  rescue StandardError => e
    log "🎵 panel could not be shown: #{e.message}"
  end

  # Turn the panel into "Music stopped", without buttons, and forget it
  def stop(guild_id)
    lock_for(guild_id).synchronize do
      message = @messages.delete(guild_id)
      message.edit("", [music_stopped_embed], Discordrb::Webhooks::View.new) if message
    end
  rescue StandardError => e
    log "🎵 panel could not be stopped: #{e.message}"
  end

  private

  # Edit the message. false when it is gone (deleted), so the caller sends a new one
  def edit_message(message, embed, view)
    message.edit("", [embed], view)
    true
  rescue Discordrb::Errors::UnknownMessage
    false
  end

  # The lock of one server, created the first time it is needed
  def lock_for(guild_id)
    @locks_guard.synchronize { @locks[guild_id] ||= Mutex.new }
  end
end
