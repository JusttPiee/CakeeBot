# The "Config" page: change the bot's limits without opening config.rb.
#
#   GET /api/config   every setting that may be changed, with its default, saved and running value
#   PUT /api/config   { "values": { "MAX_HISTORY_MESSAGES": 60 } } saves them to settings.json
#
# Nothing from .env is ever changed here. The model and temperature are shown, read-only.
require_relative '../settings_file'

module ConfigRoutes
  def self.registered(app)
    app.get '/api/config' do
      json(web_config_view)
    end

    app.put '/api/config' do
      changes = json_body["values"]
      halt json({ error: "\"values\" must be an object." }, 422) unless changes.is_a?(Hash)

      errors = web_save_config(changes)
      halt json({ errors: errors }, 422) unless errors.empty?
      json(web_config_view)
    end
  end
end

# Two saves at the same moment must not overwrite each other's changes
WEB_CONFIG_LOCK = Mutex.new

# Saves the changes on top of what is already saved. Returns the errors; nothing is written if there are any.
def web_save_config(changes)
  WEB_CONFIG_LOCK.synchronize do
    unknown = changes.keys - config_field_names
    next unknown.to_h { |name| [name, "This setting can not be changed here."] } unless unknown.empty?

    values = next_config_values.merge(changes)
    errors = config_errors(values)
    save_settings(SETTINGS_FILE, values) if errors.empty?
    errors
  end
end

def web_config_view
  saved = saved_config_values
  groups = CONFIG_GROUPS.map do |group|
    { id: group[:id], fields: group[:fields].map { |field| web_config_field_view(field, saved) } }
  end
  { restart_needed: restart_needed?, read_only: web_read_only_settings, groups: groups }
end

def web_config_field_view(field, saved)
  name = field[:name]
  field.merge(default: CONFIG_DEFAULTS[name], saved: saved[name], running: Object.const_get(name))
end

# Set in .env, so only shown. Never add a secret (a token or an API key) to this list.
def web_read_only_settings
  [{ name: "OPENAI_MODEL", value: OPENAI_MODEL }, { name: "OPENAI_TEMPERATURE", value: OPENAI_TEMPERATURE }]
end
