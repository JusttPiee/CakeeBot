# Cake's reply when a command ran but the AI's answer came back empty.
# The command really happened, so "my AI brain is unavailable" would tell the opposite.
COMMAND_DONE_REPLY = "✅ Done."

# The facts the command tools (show_help, music, manage_messages) need, taken from the Discord event.
# The AI never chooses these: permissions are checked from the real member and server.
# command_labels starts empty; a tool that ran a command adds a label like "[music: Skipped.]".
# The caller keeps this same Array and reads it after ask_ai, to see if this was a command turn.
def command_context(event, music)
  { member: event.author, server: event.server, post_channel: event.channel, music: music,
    request_message_id: event.message.id, command_labels: [], avatar_url: event.bot.profile.avatar_url }
end

# A command ran but the answer is empty: say "✅ Done." instead of "unavailable"
def done_if_command_ran(answer, labels)
  return answer if labels.empty? || !(answer.nil? || answer.strip.empty?)

  COMMAND_DONE_REPLY
end
