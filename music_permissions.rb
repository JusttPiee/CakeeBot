# Who may use the music commands and buttons. Plain functions: they only look at ids and return
# the text to tell the user, or nil when everything is fine.

# The voice channel this user is in, or nil
def music_voice_channel_id(server, user_id)
  server.voice_states[user_id]&.voice_channel&.id
end

# Why this user cannot start music right now (text), or nil.
# bot_busy: Cake is playing (or paused) in bot_channel_id.
def music_play_problem(user_channel_id, bot_channel_id, bot_busy)
  return "🎧 Join a voice channel first." if user_channel_id.nil?
  return "🎵 Cake is playing in <##{bot_channel_id}>." if bot_busy && bot_channel_id && bot_channel_id != user_channel_id

  nil
end

# Why this user cannot control the music (pause, skip, queue...), or nil.
# An admin may always stop it, even from outside voice.
def music_control_problem(user_channel_id, bot_channel_id, action, admin)
  return nil if action == :stop && admin
  return "🎵 Nothing is playing." if bot_channel_id.nil?
  return "🎧 Join <##{bot_channel_id}> to control the music." if user_channel_id != bot_channel_id

  nil
end
