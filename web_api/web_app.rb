# The web UI's API: a small Sinatra app that answers /api/... with JSON.
# It runs inside the bot (see web_server.rb), so every route can call the bot's own functions.
#
# This file holds what every route shares: the two safety checks, a few helpers, and error handling.
# The routes themselves are in web_api/routes/, one file per page of the web UI.
require 'json'
require 'sinatra/base'
require_relative './web_context'
require_relative './routes/status_routes'
require_relative './routes/user_note_routes'
require_relative './routes/memory_routes'
require_relative './routes/channel_routes'
require_relative './routes/config_routes'
require_relative './routes/log_routes'
require_relative './routes/action_routes'
require_relative './routes/static_routes'

class CakeWebApp < Sinatra::Base
  set :environment, :production # no debug pages: errors are answered by the `error` block below
  set :show_exceptions, false
  set :dump_errors, false # no backtraces in the terminal: they can contain private text
  set :context, nil

  # A ready-to-run app for one context. A subclass per context, because Sinatra settings belong to the class.
  def self.new_for(context)
    Class.new(self) { set :context, context }.new
  end

  helpers do
    def context
      settings.context
    end

    # Answer with JSON. Usage: `json(data)` at the end of a route, or `halt json({ error: "..." }, 404)`.
    def json(data, code = 200)
      status code
      content_type :json
      JSON.generate(data)
    end

    def not_found!
      halt json({ error: "Not found." }, 404)
    end

    # The Discord server this request is about. 404 unless the id is a number AND the bot is in that server,
    # so an odd id can never become part of a file path.
    def server!
      id = params[:sid].to_s
      server = id.match?(/\A\d+\z/) ? context.bot.servers[id.to_i] : nil
      server || not_found!
    end

    def server_id!
      server!.id.to_s
    end

    # A Discord id from the URL (a user or a channel), as text. 404 if it is not a number.
    def discord_id!(name)
      id = params[name].to_s
      id.match?(/\A\d+\z/) ? id : not_found!
    end

    # The request body as a Hash. 400 if it is not a JSON object.
    def json_body
      body = JSON.parse(request.body.read)
      body.is_a?(Hash) ? body : halt(json({ error: "The request must be a JSON object." }, 400))
    rescue JSON::ParserError
      halt json({ error: "The request must be a JSON object." }, 400)
    end

    def allowed_host?
      [ "localhost:#{context.port}", "127.0.0.1:#{context.port}" ].include?(request.env["HTTP_HOST"].to_s)
    end

    def valid_token?
      Rack::Utils.secure_compare(context.token.to_s, request.env["HTTP_X_CAKE_TOKEN"].to_s)
    end
  end

  # Safety check 1, for every request: the browser must have asked for localhost itself.
  # Stops "DNS rebinding", where another site's name is made to point at this computer.
  before do
    halt json({ error: "This address is not allowed." }, 403) unless allowed_host?
  end

  # Safety check 2, for the API: the request must carry the secret token (see web_token.rb).
  before '/api/*' do
    halt json({ error: "Missing or wrong token." }, 401) unless valid_token?
  end

  register StatusRoutes
  register UserNoteRoutes
  register MemoryRoutes
  register ChannelRoutes
  register ConfigRoutes
  register LogRoutes
  register ActionRoutes
  register StaticRoutes # last: it answers every address the routes above did not

  not_found do
    json({ error: "Not found." }, 404)
  end

  # A bug in a route must never take the bot down, and must not leak details to the page.
  # Only the error class is logged: the request itself could contain private text.
  error StandardError do
    log "⚠️ Web UI request failed (#{env['sinatra.error'].class})"
    json({ error: "Something went wrong in the bot. See its log." }, 500)
  end
end
