# The Discord side of MusicController: the panel and short notes in the text channel.
# These make Discord HTTP calls, so they only ever run outside the controller's @lock
# (music_controller.rb collects them in `later`).
require_relative './music_panel'
require_relative './temporary_note'

class MusicController
  private

  # Shows the panel for the song that is current right now.
  # Show and stop of one server run one at a time (panel lock) and each reads the newest state,
  # so a slow show can never bring the panel back after a stop
  def refresh_panel(guild_id)
    panel_lock(guild_id).synchronize do
      args = @lock.synchronize { panel_args(guild_id) }
      @poster.show(*args) if args
    end
  end

  # Marks the panel stopped, unless music started again meanwhile
  def stop_panel(guild_id)
    panel_lock(guild_id).synchronize do
      busy = @lock.synchronize { !@servers[guild_id]&.queue&.current.nil? }
      @poster.stop(guild_id) unless busy
    end
  end

  # [guild_id, channel, embed, view] for the poster, or nil when nothing is current
  def panel_args(guild_id)
    state = @servers[guild_id]
    track = state&.queue&.current
    return nil if track.nil? || state.text_channel.nil?

    paused = state.queue.paused
    embed = music_panel_embed(track, state.queue.size, paused, state.volume)
    [guild_id, state.text_channel, embed, music_panel_view(paused)]
  end

  def panel_lock(guild_id)
    @lock.synchronize { @panel_locks[guild_id] ||= Mutex.new }
  end

  # Queues a message for the server's text channel (it stays)
  def note(state, later, text)
    channel = state.text_channel
    later << -> { post_note(channel, text) } if channel
  end

  # Queues a short message for the server's text channel that deletes itself after MUSIC_NOTE_SECONDS
  def temporary_note(state, later, text)
    channel = state.text_channel
    later << -> { post_temporary_note(channel, text) } if channel
  end

  def post_note(channel, text)
    channel.send_message(text)
  rescue StandardError => e
    log "🎵 Could not post a music note: #{e.message}"
  end

  def post_temporary_note(channel, text)
    send_temporary_note(channel, text, MUSIC_NOTE_SECONDS)
  rescue StandardError => e
    log "🎵 Could not post a music note: #{e.message}"
  end
end
