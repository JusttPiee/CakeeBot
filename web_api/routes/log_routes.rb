# The "Logs" page: read the bot's log files.
#
#   GET /api/logs/days                     the days that have logs, newest first
#   GET /api/logs?day=2026-11-11           the last lines of that day
#   GET /api/logs?day=2026-11-11&after=40  only the lines after the first 40 (what the page asks every 2 seconds)
require_relative '../log_reader'

module LogRoutes
  def self.registered(app)
    app.get '/api/logs/days' do
      json(log_days)
    end

    app.get '/api/logs' do
      day = params[:day].to_s
      not_found! unless LOG_DAY_FORMAT.match?(day) # the day becomes a folder name, so it must look like a date

      after = params[:after].to_s.match?(/\A\d+\z/) ? params[:after].to_i : nil
      json(read_log_lines(day, after))
    end
  end
end
