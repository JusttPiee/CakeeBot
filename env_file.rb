# Small decisions about the .env file, made by cakee.rb before .env is loaded.

# First run on a PC: .env is built from .env.example. Not in Docker: there the settings come from compose.yaml.
def create_env_from_template?(env_file, template, data_dir_set)
  !data_dir_set && !File.exist?(env_file) && File.exist?(template)
end

# Dotenv never replaces a variable that exists, even a blank one ("WEB_UI_TOKEN=" in Docker's env_file).
# Removing the blank ones lets the value saved in the bot's own .env through.
def drop_blank_variables(names, env = ENV)
  names.each { |name| env.delete(name) if env[name].to_s.strip.empty? }
end

# Which file an error message should tell people to edit
def settings_place(env_file, data_dir_set)
  data_dir_set ? "the .env file next to compose.yaml (then run: docker compose up -d)" : env_file
end
