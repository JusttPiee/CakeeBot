# Where the files the bot writes live: memory, logs, settings, AI channels, bad words.
# - Normally: the project folder, next to the code.
# - In Docker: the folder in CAKE_DATA_DIR (compose.yaml mounts it), so the files survive an update.
# Keep this file free of config.rb and .env: message_logger.rb needs it before .env is loaded.
require 'fileutils'

def data_dir_from(env)
  folder = env['CAKE_DATA_DIR'].to_s.strip
  folder.empty? ? __dir__ : File.expand_path(folder)
end

# True when the data was moved out of the project folder (Docker)
def data_dir_set?(env = ENV)
  !env['CAKE_DATA_DIR'].to_s.strip.empty?
end

DATA_DIR = data_dir_from(ENV)

def data_path(name, dir = DATA_DIR)
  File.join(dir, name)
end

# The personality sits with the prompts, or in the data folder when there is one (nil = there is none)
def personality_path(data_dir)
  data_dir.nil? ? File.join(__dir__, 'prompts', 'personality.txt') : data_path('personality.txt', data_dir)
end

# Gives a new data folder its first copy of a file that comes with the code. An existing file is never touched.
def seed_data_file(name, dir = DATA_DIR, source_dir = __dir__)
  target = data_path(name, dir)
  return if File.exist?(target)

  FileUtils.mkdir_p(dir)
  FileUtils.cp(File.join(source_dir, name), target)
end

BAD_WORDS_FILE = data_path('badwords.txt')
AI_CONFIG_FILE = data_path('ai_config.txt')
