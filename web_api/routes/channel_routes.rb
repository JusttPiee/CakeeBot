# The "AI channels" page: which channels Cake answers every message in.
#
#   GET /api/servers/:sid/channels          every text channel, with its AI state
#   PUT /api/servers/:sid/channels/:cid/ai  { "on": true } or { "on": false }
#
# A switch here does what !neuronactivate / !neurondeactivate do (see ai_mode.rb), but silently:
# nothing is posted in the channel. It works right away, without a restart.
require_relative '../../ai_mode'

module ChannelRoutes
  def self.registered(app)
    app.get '/api/servers/:sid/channels' do
      json(web_channel_list(server!, context.ai_config_path))
    end

    app.put '/api/servers/:sid/channels/:cid/ai' do
      server = server!
      channel = web_find_channel(server, discord_id!(:cid)) || not_found!
      on = json_body["on"]
      halt json({ error: "\"on\" must be true or false." }, 422) unless [true, false].include?(on)
      halt json({ error: "Cake can't read this channel." }, 422) if on && !web_channel_readable?(server, channel)

      web_switch_ai_mode(context, server, channel, on)
      json({ id: channel.id.to_s, ai_on: on })
    end
  end
end

# --- what each route does ---

def web_channel_list(server, config_path)
  ai_channels = load_ai_channels(config_path)
  server.text_channels.map do |channel|
    { id: channel.id.to_s, name: channel.name, ai_on: ai_channels.include?(channel.id.to_s),
      readable: web_channel_readable?(server, channel) }
  end
end

def web_find_channel(server, channel_id)
  server.text_channels.find { |channel| channel.id.to_s == channel_id }
end

# AI mode needs to see new messages and to load the recent ones. server.bot is Cake's own member in that server.
def web_channel_readable?(server, channel)
  server.bot.permission?(:read_messages, channel) && server.bot.permission?(:read_message_history, channel)
end

def web_switch_ai_mode(context, server, channel, on)
  if on
    web_turn_ai_mode_on(context, channel)
  else
    turn_ai_mode_off(context.histories, context.ai_config_path, channel.id)
  end
  log "🧠 AI mode turned #{on ? 'on' : 'off'} in #{server.name} ##{channel.name} (web UI)"
end

# If the recent messages can't be loaded (Discord is down), the channel is taken off the list again:
# a channel that is "on" with no memory would answer without knowing the conversation.
def web_turn_ai_mode_on(context, channel)
  loader = context.history_loader || method(:load_reading_channel_history)
  turn_ai_mode_on(context.bot, context.histories, context.ai_config_path, channel, loader)
rescue StandardError
  turn_ai_mode_off(context.histories, context.ai_config_path, channel.id)
  raise
end
