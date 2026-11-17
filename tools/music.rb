# Tool: control the voice music for the person talking. Permissions are checked in music_ai_action,
# from the real voice channels, never from the arguments. Not available in !silent.
require_relative '../music_ai_actions'
require_relative '../command_labels'

MUSIC_DEFINITION = {
  type: "function",
  name: "music",
  description: "Play or control music in the voice channel of the person talking to you. Use it when they ask you to " \
               "play a song, skip, pause, resume, change the volume, show, shuffle or clear the queue, " \
               "loop (repeat) the song or the queue, or stop. " \
               "Use set_volume only for an exact number; for \"louder\" or \"quieter\" use volume_up or volume_down. " \
               "loop_song repeats the current song, loop_queue repeats the whole queue, loop_off stops repeating. " \
               "Tell the person what the result says, nothing more.",
  parameters: {
    type: "object",
    properties: {
      action: { type: "string", enum: MUSIC_AI_ACTIONS, description: "What to do" },
      query: { type: "string", description: "For play: a link or a song name. Otherwise \"\"" },
      level: { type: "integer", description: "For set_volume: the exact volume 0 to 100. Otherwise -1" }
    },
    required: %w[action query level]
  }
}.freeze

def run_music(arguments, context)
  return SILENT_COMMAND_TEXT if context[:silent]

  action = arguments["action"].to_s
  level = music_level(arguments["level"])
  result = music_ai_action(context[:music], context[:server], context[:member], context[:post_channel], action,
                           query: arguments["query"].to_s, level: level)
  add_music_label(context, action, result)
  result
end

# The level as the AI gave it. -1, "" or nothing means no level (nil); anything else goes on raw,
# so music_ai_set_volume can refuse a non-number instead of turning it into 0
def music_level(value)
  text = value.to_s.strip
  text.empty? || text == "-1" ? nil : value
end

# A refusal or "music is not available" is not a command turn, so it gets no label
def add_music_label(context, action, result)
  return if result.start_with?("Refused:") || result == MUSIC_UNAVAILABLE_TEXT

  add_command_label(context, action == "queue" ? "music: showed the queue" : "music: #{result}")
end
