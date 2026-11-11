# The buttons of the web UI that run a bot command.
#
#   POST /api/restart                       restart the bot (the same as typing /restart in the terminal)
#   GET  /api/servers/:sid/buildmemory      is a build running, and what did the last one report?
#   POST /api/servers/:sid/buildmemory      run !buildmemory for that server, in the background
#
# Both commands answer right away (202 = "accepted, working on it") and do the work on another thread.
# A second click while the first is still working gets 409 ("conflict"), so nothing ever runs twice.
require 'time'
require_relative '../../build_memory'
require_relative '../../terminal_commands'

module ActionRoutes
  def self.registered(app)
    app.post '/api/restart' do
      halt json({ error: "A restart is already on its way." }, 409) unless web_request_restart(context)
      json({ ok: true }, 202)
    end

    app.get '/api/servers/:sid/buildmemory' do
      json(web_memory_build_state(server_id!))
    end

    app.post '/api/servers/:sid/buildmemory' do
      halt json({ error: "already running" }, 409) unless web_start_memory_build(context, server!)
      json({ ok: true }, 202)
    end
  end
end

# --- restart ---

WEB_RESTART_DELAY_SECONDS = 0.5 # long enough for the "ok" answer to reach the page before the bot exits
WEB_RESTART_STATE = { pending: false }
WEB_RESTART_LOCK = Mutex.new

# Returns false if a restart was already requested
def web_request_restart(context)
  WEB_RESTART_LOCK.synchronize do
    return false if WEB_RESTART_STATE[:pending]

    WEB_RESTART_STATE[:pending] = true
  end
  log "🔄 Restart requested from the web UI"
  Thread.new { web_restart_soon(context) }
  true
end

# context.restarter is only set by tests. The real restart_bot ends the whole program (see terminal_commands.rb).
def web_restart_soon(context)
  sleep WEB_RESTART_DELAY_SECONDS
  context.restarter ? context.restarter.call : restart_bot(context.bot)
ensure
  WEB_RESTART_LOCK.synchronize { WEB_RESTART_STATE[:pending] = false }
end

# --- !buildmemory ---

# server id => { text:, finished_at: } of the last build started from the web UI. In RAM only.
WEB_BUILD_REPORTS = {}
WEB_BUILD_REPORTS_LOCK = Mutex.new

def web_memory_build_state(server_id)
  last = WEB_BUILD_REPORTS_LOCK.synchronize { WEB_BUILD_REPORTS[server_id] } || {}
  { running: memory_build_running?(server_id), last_report: last[:text], finished_at: last[:finished_at] }
end

# Returns false if a build is already running in this server (started here or with !buildmemory)
def web_start_memory_build(context, server)
  return false unless start_memory_build?(server.id)

  log "🧠 !buildmemory started from the web UI in #{server.name}"
  Thread.new { web_run_memory_build(context, server) }
  true
end

def web_run_memory_build(context, server)
  text = web_memory_build_text(context, server)
  report = { text: text, finished_at: Time.now.iso8601 }
  WEB_BUILD_REPORTS_LOCK.synchronize { WEB_BUILD_REPORTS[server.id.to_s] = report }
ensure
  finish_memory_build(server.id)
end

# context.build_channels is only set by tests. Listing the channels can fail too (Discord down), so it is inside the rescue.
def web_memory_build_text(context, server)
  channels = context.build_channels ? context.build_channels.call(server) : server_reading_channels(server, context.bot)
  memory_build_result_text(context.client, server.id, server.name, channels, server.bot.display_name)
rescue StandardError => e
  log "❗ !buildmemory failed in #{server.name} (#{e.class})"
  "❗ Building memory failed, please try again later."
end
