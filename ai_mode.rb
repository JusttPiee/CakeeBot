# Turning AI mode on or off in a channel. Used by !neuronactivate / !neurondeactivate (cakee.rb)
# and by the web UI (web_api/routes/channel_routes.rb), so both always do exactly the same thing.
#
# AI mode is two things that must change together:
#   1. the saved list of AI channels (ai_config.txt), so it survives a restart
#   2. the channel's chat memory in RAM (histories), which the AI replies are built from
require_relative './ai_config'
require_relative './channel_lock'
require_relative './channel_reader'
require_relative './discord_history'

# Saves the channel and starts its chat memory from its recent messages.
# Returns false if AI mode was already on there (the memory is loaded fresh anyway).
# loader: only tests pass one, to avoid calling Discord.
def turn_ai_mode_on(bot, histories, config_path, channel, loader = method(:load_reading_channel_history))
  added = add_ai_channel(config_path, channel.id)
  with_channel_lock(channel.id) do # no reply may be written while the memory is being replaced
    histories[channel.id] = loader.call(bot, channel)
  end
  added
end

# Returns false, and changes nothing, if AI mode was not on in this channel.
def turn_ai_mode_off(histories, config_path, channel_id)
  return false unless remove_ai_channel(config_path, channel_id)

  histories.delete(channel_id) # free this channel's memory
  true
end

# The channel's recent messages as a chat history. Names come from Discord's JSON, see discord_history.rb.
def load_reading_channel_history(bot, channel)
  load_ai_channel_history(ReadingChannel.new(channel, bot), bot.profile.id)
end
