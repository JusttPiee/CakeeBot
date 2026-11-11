# Reading and writing settings.json for the web UI's Config page.
# config.rb reads the file once when the bot starts (see saved_setting there), so a saved change
# only takes effect after a restart. That is what restart_needed? tells the page.
require 'json'
require_relative './config_fields'

# The saved values the Config page may show: only known settings with a valid value.
# Anything else in a hand-edited file is ignored here, just like config.rb ignores it.
def saved_config_values(path = SETTINGS_FILE)
  saved = read_saved_settings(path)
  config_fields.each_with_object({}) do |field, values|
    name = field[:name]
    values[name] = saved[name] if saved.key?(name) && config_value_error(field, saved[name]).nil?
  end
end

# The value every setting will have after the next restart: the saved one, or else the default
def next_config_values(path = SETTINGS_FILE)
  CONFIG_DEFAULTS.slice(*config_field_names).merge(saved_config_values(path))
end

# Only values that differ from the default are kept, so the file stays small and a later change
# of a default in config.rb still reaches the settings nobody touched.
# Written to a temp file first, then renamed: the bot never starts with a half-written file.
def save_settings(path, values)
  changed = values.select { |name, value| config_field_names.include?(name) && value != CONFIG_DEFAULTS[name] }
  temp_path = "#{path}.tmp"
  File.write(temp_path, "#{JSON.pretty_generate(changed)}\n", encoding: "UTF-8")
  File.rename(temp_path, path)
end

# True when a saved value is not the one the running bot uses
def restart_needed?(path = SETTINGS_FILE)
  next_config_values(path).any? { |name, value| Object.const_get(name) != value }
end
