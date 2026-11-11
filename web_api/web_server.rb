# Starts the web UI: the Sinatra app (web_app.rb) served by Puma on a background thread of the bot.
# cakee.rb calls start_web_ui once Discord is connected.
#
# It listens on 127.0.0.1 only, so only this computer can open it.
# If it can't start (the port is taken, for example), the bot just keeps running without it.
#
# Settings in .env: WEB_UI=off turns it off, WEB_UI_PORT changes the port, WEB_UI_TOKEN is made automatically.
require 'puma'
require 'puma/server'
require_relative '../config'
require_relative './web_app'
require_relative './web_token'

WEB_UI_DEFAULT_PORT = 4567
WEB_UI_ALLOWED_PORTS = (1024..65_535) # below 1024 needs admin rights
WEB_UI_HOST = "127.0.0.1"
WEB_UI_STATE = { started: false, server: nil }

def web_ui_enabled?
  setting('WEB_UI', default: 'on').downcase != 'off'
end

def web_ui_port
  text = setting('WEB_UI_PORT', default: WEB_UI_DEFAULT_PORT.to_s)
  port = text.match?(/\A\d+\z/) ? text.to_i : WEB_UI_DEFAULT_PORT
  WEB_UI_ALLOWED_PORTS.cover?(port) ? port : WEB_UI_DEFAULT_PORT
end

# Returns the running server, or nil if the web UI is off or could not start.
# Safe to call again: Discord's "ready" event fires after every reconnect, the web UI starts only once.
def start_web_ui(bot, client, histories, ai_config_path, env_file)
  return WEB_UI_STATE[:server] if WEB_UI_STATE[:started]

  WEB_UI_STATE[:started] = true
  return nil unless web_ui_enabled?

  context = WebContext.new(bot: bot, client: client, histories: histories, ai_config_path: ai_config_path,
                           token: load_or_create_web_token(env_file), port: web_ui_port, started_at: Time.now)
  WEB_UI_STATE[:server] = start_web_server_safely(CakeWebApp.new_for(context), context.port)
  announce_web_ui(context) if WEB_UI_STATE[:server]
  WEB_UI_STATE[:server]
end

# A web UI that can't start must never stop the bot
def start_web_server_safely(app, port)
  run_web_server(app, port)
rescue StandardError => e
  log "⚠️ Web UI could not start (#{e.class}). The bot keeps running without it."
  nil
end

# Puma answers requests on its own threads (at most 4 at a time, plenty for one person), so the bot is never blocked.
def run_web_server(app, port)
  server = Puma::Server.new(app, nil, { min_threads: 0, max_threads: 4, log_writer: Puma::LogWriter.null })
  server.add_tcp_listener(WEB_UI_HOST, port)
  server.run # returns right away; the server keeps running in the background
  server
end

# The link with the token is printed with puts, not log: the token must not end up in the log files.
def announce_web_ui(context)
  log "🌐 Web UI: http://localhost:#{context.port}"
  puts "   First time in this browser? Open: http://localhost:#{context.port}/?token=#{context.token}"
end
