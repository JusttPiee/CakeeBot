# GET /api/status: who the bot is and which servers it is in.
# The web page asks this every few seconds, so it also notices when the bot is down or has restarted.
require 'time' # Time#iso8601
require_relative '../settings_file'

module StatusRoutes
  def self.registered(app)
    app.get '/api/status' do
      bot = context.bot
      servers = bot.servers.values.map { |server| { id: server.id.to_s, name: server.name, icon_url: server.icon_url } }
      json({ bot_name: bot.profile.username, started_at: context.started_at.iso8601,
             restart_needed: restart_needed?, servers: servers })
    end
  end
end
