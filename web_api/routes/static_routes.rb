# Serves the web page itself: the React app after `npm run build` (the files in web/dist).
# It must be registered last, because it answers every GET the API routes did not.
#
# The React app decides what to show from the address (/memory/people, /config...). Those addresses are
# not files, so any address that is not a real file gets index.html, and React takes it from there.
# No token is needed here: these files are the same for everyone and contain no data.

# Tests point this at a temp folder.
WEB_DIST_DIR = ENV['CAKE_TEST_WEB_DIST'] || File.expand_path('../../web/dist', __dir__)

WEB_NOT_BUILT_PAGE = <<~HTML
  <!doctype html>
  <meta charset="utf-8">
  <title>CakeeBot Admin</title>
  <body style="font-family: system-ui, sans-serif; background: #313338; color: #dbdee1; padding: 40px; line-height: 1.6">
    <h1>The web UI is not built yet</h1>
    <p>Cake is running, but the web page has not been built. In a terminal, in the bot's folder, run:</p>
    <pre style="background: #1e1f22; padding: 16px; border-radius: 8px">cd web
  npm install
  npm run build</pre>
    <p>Then reload this page. You only need to do this once, and again after the web UI's code changes.</p>
  </body>
HTML

module StaticRoutes
  def self.registered(app)
    app.get '/*' do
      not_found! if request.path_info.start_with?("/api/") # an unknown API address is an error, not a page

      file = web_static_file(request.path_info)
      next send_file(file) if file

      index = web_static_file("/index.html")
      next WEB_NOT_BUILT_PAGE if index.nil?

      cache_control :no_cache # always the newest page after a rebuild; its scripts have new names each build
      send_file(index)
    end
  end
end

# The file in web/dist for this address, or nil if there is none.
# The resolved path must stay inside web/dist, so no address can reach another file of the bot (like .env).
def web_static_file(url_path, dist_dir = WEB_DIST_DIR)
  dist = File.expand_path(dist_dir)
  full_path = File.expand_path(url_path.delete_prefix("/"), dist)
  full_path.start_with?("#{dist}/") && File.file?(full_path) ? full_path : nil
end
