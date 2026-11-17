# Music actions the AI can do for a person (the "music" tool). Same rules as the typed commands:
# music_play_problem / music_control_problem decide who may do what, checked from the real
# voice states and never from tool arguments. Everything returns a String and posts nothing;
# the music panel is still posted by the controller.
require_relative './config'
require_relative './music_commands'

MUSIC_AI_ACTIONS = %w[play skip skip_playlist pause resume volume_up volume_down set_volume queue clear_queue stop].freeze

MUSIC_AI_NOTHING_PLAYING = "Nothing is playing."
MUSIC_AI_PLAY_USAGE = "Refused: say what to play (a link or a song name)."
MUSIC_AI_VOLUME_USAGE = "Refused: give a volume from 0 to 100."

# Does one music action for this member. Returns the text to tell the AI.
# finder and parts are only replaced in tests.
def music_ai_action(controller, server, member, text_channel, action, query: "", level: nil,
                    finder: method(:find_music), parts: method(:music_missing_parts))
  return MUSIC_UNAVAILABLE_TEXT if controller.nil? || music_unavailable?(controller, parts)
  return "Unknown music action: #{action}." unless MUSIC_AI_ACTIONS.include?(action.to_s)

  action = action.to_s
  return music_ai_play(controller, server, member, text_channel, query, finder) if action == "play"

  problem = music_ai_control_problem(controller, server, member, action)
  return "Refused: #{problem}" if problem

  music_ai_run(controller, server.id, action, level)
end

# --- permissions ---

# Why this member cannot play right now (text), or nil. Voice channels are read fresh each time.
def music_ai_play_problem(controller, server, member)
  music_play_problem(music_voice_channel_id(server, member.id),
                     controller.voice_channel_id(server.id), controller.busy?(server.id))
end

# Why this member cannot control the music, or nil. Only "stop" lets an admin act from anywhere.
def music_ai_control_problem(controller, server, member, action)
  symbol = action == "stop" ? :stop : action.to_sym
  admin = member.permission?(:administrator) ? true : false
  music_control_problem(music_voice_channel_id(server, member.id), controller.voice_channel_id(server.id), symbol, admin)
end

# --- play ---

# Check, search (slow), check again, then add the songs
def music_ai_play(controller, server, member, text_channel, query, finder)
  query = query.to_s.strip
  return MUSIC_AI_PLAY_USAGE if query.empty?

  problem = music_ai_play_problem(controller, server, member)
  return "Refused: #{problem}" if problem

  result = finder.call(query, member.id)
  return "Could not play: #{result.error}" if result.error

  music_ai_add_songs(controller, server, member, text_channel, result)
end

# The search can take long, so the problem is checked again before the songs are added
def music_ai_add_songs(controller, server, member, text_channel, result)
  problem = music_ai_play_problem(controller, server, member)
  return "Refused: #{problem}" if problem

  voice_id = music_voice_channel_id(server, member.id)
  outcome = controller.play(server.id, voice_id, text_channel, result.tracks)
  return music_added_text(result) if music_say_added?(outcome, result)

  "Playing #{music_safe_text(result.tracks.first.title)}."
end

# --- the other actions ---

# Runs a control action (permission already checked) and returns its text
def music_ai_run(controller, guild_id, action, level)
  case action
  when "skip", "skip_playlist", "clear_queue", "stop" then music_ai_queue_action(controller, guild_id, action)
  when "pause", "resume" then music_ai_pause(controller, guild_id, action)
  when "volume_up", "volume_down", "set_volume" then music_ai_volume(controller, guild_id, action, level)
  when "queue" then music_queue_message(*controller.queue_snapshot(guild_id))
  end
end

# skip, skip_playlist, clear_queue, stop
def music_ai_queue_action(controller, guild_id, action)
  case action
  when "skip" then controller.skip(guild_id) ? "Skipped." : "Nothing to skip."
  when "skip_playlist" then "Skipped the playlist (#{controller.skip_playlist(guild_id)} songs)."
  when "clear_queue" then "Cleared #{controller.clear_queue(guild_id)} songs from the queue."
  when "stop"
    controller.stop(guild_id)
    "Stopped the music."
  end
end

# pause or resume
def music_ai_pause(controller, guild_id, action)
  paused = action == "pause"
  return paused ? "Paused." : "Resumed." if controller.set_paused(guild_id, paused)

  "Nothing to #{action}."
end

# volume_up, volume_down, set_volume
def music_ai_volume(controller, guild_id, action, level)
  new_level =
    case action
    when "volume_up" then controller.change_volume(guild_id, MUSIC_VOLUME_STEP)
    when "volume_down" then controller.change_volume(guild_id, -MUSIC_VOLUME_STEP)
    else return music_ai_set_volume(controller, guild_id, level)
    end
  music_ai_volume_text(new_level)
end

# An exact level: it must be a whole number
def music_ai_set_volume(controller, guild_id, level)
  number = Integer(level.to_s.delete_suffix('%'), 10, exception: false)
  return MUSIC_AI_VOLUME_USAGE if number.nil?

  music_ai_volume_text(controller.set_volume(guild_id, number))
end

# "Volume is now 40%.", or a note when Cake is not in voice (the level is nil)
def music_ai_volume_text(level)
  level ? "Volume is now #{level}%." : MUSIC_AI_NOTHING_PLAYING
end
