# The music commands (!play, !pause, ...), the panel buttons, and the voice-channel watcher.
# cakee.rb registers these. Every entry point rescues StandardError and logs one "🎵" line,
# so a music problem never reaches discordrb and never stops chat, AI or memory.
# Short problems go to the channel as a note that deletes itself, or to the button user only (ephemeral).
require_relative './config'
require_relative './music_sources'
require_relative './music_bridge'
require_relative './music_panel'
require_relative './music_permissions'
require_relative './temporary_note'

MUSIC_UNAVAILABLE_TEXT = "🎵 Music is not available right now."
MUSIC_PLAY_USAGE = "Usage: `!play <link or song name>`"
MUSIC_MESSAGE_LIMIT = 2000 # Discord's limit for one message
MUSIC_QUEUE_CUT = 1900 # the queue text is cut to this, leaving room for the "..." line

# Panel button id => the action it does
MUSIC_BUTTON_ACTIONS = {
  'music:toggle' => :toggle,
  'music:skip' => :skip,
  'music:skipplaylist' => :skipplaylist,
  'music:queue' => :queue,
  'music:clearqueue' => :clearqueue,
  'music:voldown' => :voldown,
  'music:volup' => :volup
}.freeze

MUSIC_VOLUME_USAGE = "Usage: `!volume <0-100>`"

# --- commands ---

# One music command (!play, !volume, !pause, !resume, !skip, !skipplaylist, !queue, !clearqueue, !stop). Returns nil.
# parts and finder are only replaced in tests.
def music_command(event, action, args, controller, parts: method(:music_missing_parts), finder: method(:find_music))
  return nil if event.server.nil?
  return music_note(event, MUSIC_UNAVAILABLE_TEXT) if music_unavailable?(controller, parts)

  if action == :play
    music_play(event, args, controller, finder)
  elsif action == :volume
    music_volume(event, args, controller)
  else
    music_control(event, action, controller)
  end
  nil
rescue StandardError => e
  log "🎵 !#{action} failed (#{e.class}): #{e.message}"
  nil
end

# A short note in the channel that deletes itself. Returns nil
def music_note(event, text)
  send_temporary_note(event.channel, text, MUSIC_NOTE_SECONDS)
  nil
end

# Music is off in the settings, a program is missing, or Node is not ready
def music_unavailable?(controller, parts)
  return true unless MUSIC_ENABLED == 'on'
  return true unless parts.call.empty?

  !controller.available?
end

# !play: check the user can use it, then search (slow), check again, then add the songs
def music_play(event, args, controller, finder)
  text = args.join(' ').strip
  return event.respond(MUSIC_PLAY_USAGE) if text.empty?

  problem = music_current_play_problem(event, controller)
  return music_note(event, problem) if problem

  result = finder.call(text, event.user.id)
  return event.respond(result.error) if result.error

  add_found_songs(event, controller, result)
end

# The play problem right now (voice channels and busy state are read fresh each time), or nil
def music_current_play_problem(event, controller)
  guild_id = event.server.id
  music_play_problem(music_voice_channel_id(event.server, event.user.id),
                     controller.voice_channel_id(guild_id), controller.busy?(guild_id))
end

# The search can take a long time, so the problem is checked again before the songs are added.
# Then hands the songs to the controller and says what was added (see music_say_added?).
def add_found_songs(event, controller, result)
  problem = music_current_play_problem(event, controller)
  return music_note(event, problem) if problem

  voice_id = music_voice_channel_id(event.server, event.user.id)
  outcome = controller.play(event.server.id, voice_id, event.channel, result.tracks)
  event.respond(music_added_text(result)) if music_say_added?(outcome, result)
end

# Say "➕ Added ..." when the songs only joined the queue (the panel does not show them),
# and for every playlist, so people know how many songs came in and whether it was cut
def music_say_added?(outcome, result)
  outcome == :queued || result.tracks.length > 1 || result.cut_off
end

# "➕ Added <title>" or "➕ Added N songs from <playlist>", plus a note when the playlist was cut
def music_added_text(result)
  tracks = result.tracks
  text = tracks.length == 1 ? "➕ Added #{music_safe_text(tracks.first.title)}" : "➕ Added #{tracks.length} songs#{music_playlist_part(tracks.first)}"
  text += " (only the first #{MUSIC_PLAYLIST_LIMIT})" if result.cut_off
  text
end

# " from <playlist>", or nothing when the songs have no playlist name
def music_playlist_part(track)
  track.playlist_name.to_s.empty? ? "" : " from #{music_safe_text(track.playlist_name)}"
end

# Titles come from the internet: stop "@everyone" and "@here" from pinging anyone
def music_safe_text(text)
  text.to_s.gsub("@", "@​")
end

# Everything except !play: check the user, do it, say so only when nothing happened
def music_control(event, action, controller)
  guild_id = event.server.id
  problem = music_user_problem(event, action, controller)
  return music_note(event, problem) if problem
  return event.respond(music_queue_message(*controller.queue_snapshot(guild_id))) if action == :queue

  note = music_run_action(action, guild_id, controller)
  music_note(event, note) if note
end

# !volume 30 sets the level, !volume alone shows it. Same rule as the other controls:
# only people in Cake's voice channel
def music_volume(event, args, controller)
  problem = music_user_problem(event, :volume, controller)
  return music_note(event, problem) if problem

  guild_id = event.server.id
  return music_note(event, music_volume_text(controller.volume(guild_id))) if args.empty?

  level = music_volume_level(args.first)
  return music_note(event, MUSIC_VOLUME_USAGE) if level.nil?

  music_note(event, music_volume_text(controller.set_volume(guild_id, level)))
end

# "30" or "30%" => 30. Anything else => nil
def music_volume_level(text)
  Integer(text.to_s.delete_suffix('%'), 10, exception: false)
end

# "🔊 Volume: 30%", or "Nothing is playing." when Cake is not in voice (the level is nil)
def music_volume_text(level)
  level ? "🔊 Volume: #{level}%" : "🎵 Nothing is playing."
end

# Why this user cannot control the music, or nil
def music_user_problem(event, action, controller)
  admin = music_admin?(event.user)
  music_control_problem(music_voice_channel_id(event.server, event.user.id), controller.voice_channel_id(event.server.id), action, admin)
end

# Is this person a server administrator?
def music_admin?(user)
  user.permission?(:administrator) ? true : false
end

# Does the action. Returns a short note when there was nothing to do, otherwise nil.
# The panel itself is updated by the controller.
def music_run_action(action, guild_id, controller)
  case action
  when :toggle then controller.toggle_pause(guild_id).nil? ? "🎵 Nothing is playing." : nil
  when :pause then controller.set_paused(guild_id, true) ? nil : "🎵 Nothing to pause."
  when :resume then controller.set_paused(guild_id, false) ? nil : "🎵 Nothing to resume."
  when :skip then controller.skip(guild_id) ? nil : "🎵 Nothing to skip."
  when :skipplaylist then music_do_and_say_nothing { controller.skip_playlist(guild_id) }
  when :clearqueue then music_do_and_say_nothing { controller.clear_queue(guild_id) }
  when :stop then music_do_and_say_nothing { controller.stop(guild_id) }
  when :voldown then controller.change_volume(guild_id, -MUSIC_VOLUME_STEP) ? nil : "🎵 Nothing is playing."
  when :volup then controller.change_volume(guild_id, MUSIC_VOLUME_STEP) ? nil : "🎵 Nothing is playing."
  end
end

# Runs the block and returns nil (no note), whatever the block returns
def music_do_and_say_nothing
  yield
  nil
end

# --- the queue text ---

# The text for !queue and the Queue button, always under Discord's message limit
def music_queue_message(current, waiting)
  fit_music_message(music_safe_text(music_queue_text(current, waiting)))
end

# Cuts a long text at a line end and adds "..." so it fits in one message
def fit_music_message(text)
  return text if text.length <= MUSIC_MESSAGE_LIMIT

  cut = text[0, MUSIC_QUEUE_CUT]
  line_end = cut.rindex("\n")
  cut = cut[0, line_end] if line_end
  "#{cut}\n..."
end

# --- buttons ---

# A press on a panel button. Problems and the queue are shown only to the person who pressed. Returns nil.
def music_button(event, controller, parts: method(:music_missing_parts))
  action = MUSIC_BUTTON_ACTIONS[event.custom_id]
  return nil if action.nil? || event.server.nil?
  return music_private(event, MUSIC_UNAVAILABLE_TEXT) if music_unavailable?(controller, parts)

  problem = music_user_problem(event, action, controller)
  return music_private(event, problem) if problem

  music_button_action(event, action, controller)
  nil
rescue StandardError => e
  log "🎵 button #{event.custom_id} failed (#{e.class}): #{e.message}"
  nil
end

# Runs the button's action. The queue is shown privately.
# For the other buttons Discord gets its answer first (defer_update), because the action can be slow
# and Discord shows "This interaction failed" after 3 seconds. A "nothing to do" note then comes
# as a private follow-up message.
def music_button_action(event, action, controller)
  guild_id = event.server.id
  return music_private(event, music_queue_message(*controller.queue_snapshot(guild_id))) if action == :queue

  event.defer_update
  note = music_run_action(action, guild_id, controller)
  event.send_message(content: note, ephemeral: true) if note
end

# A reply only the person who pressed the button can see. Returns nil
def music_private(event, text)
  event.respond(content: text, ephemeral: true)
  nil
end

# --- voice channel watcher ---

# Someone joined or left a voice channel. When it is Cake's channel, tells the controller how many
# people (not bots) are still there, so Cake can leave an empty channel.
# When someone dragged Cake itself to another channel, the music stops.
def music_voice_update(event, controller)
  return nil if event.server.nil?

  cake_channel_id = controller.voice_channel_id(event.server.id)
  return music_stop_after_move(event, controller) if music_cake_moved?(event, cake_channel_id)

  channel = music_changed_channel(event, cake_channel_id)
  return nil if channel.nil?

  controller.listeners_changed(event.server.id, music_humans_in(channel))
  nil
rescue StandardError => e
  log "🎵 voice update failed (#{e.class}): #{e.message}"
  nil
end

# Did someone move Cake to a voice channel other than the one the controller knows?
# Cake's own joins and moves are not caught: the controller remembers the new channel before Node joins it.
# Cake leaving voice entirely (no new channel) is not a move: Node reports it as "disconnected".
def music_cake_moved?(event, cake_channel_id)
  return false if cake_channel_id.nil? || event.channel.nil? || event.user.nil?
  return false unless event.user.id == event.bot.profile.id

  event.channel.id != cake_channel_id
end

# Cake was moved: stop the music (clear the queue, leave, mark the panel stopped). Returns nil
def music_stop_after_move(event, controller)
  log "🎵 Cake was moved to another voice channel in server #{event.server.id}, stopping"
  controller.stop(event.server.id)
  nil
end

# The channel of this event that is Cake's channel (the one joined or the one left), or nil
def music_changed_channel(event, cake_channel_id)
  return nil if cake_channel_id.nil?

  [event.channel, event.old_channel].compact.find { |channel| channel.id == cake_channel_id }
end

# How many people (not bots) are in this voice channel
def music_humans_in(channel)
  channel.users.count { |member| !member.bot_account? }
end
