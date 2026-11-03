# The channels where AI mode is on (!neuronactivate), saved so they survive a restart.
# The file has one channel ID per line. An old file with a single ID still works.

# All AI channel IDs, as text (e.g. ["1382043745305755748"]). Empty list if none.
def load_ai_channels(file_path)
  return [] unless File.exist?(file_path)

  File.readlines(file_path, chomp: true).map(&:strip).reject(&:empty?).uniq
end

def save_ai_channels(file_path, channel_ids)
  File.write(file_path, channel_ids.map { |id| "#{id}\n" }.join)
end

def ai_channel?(file_path, channel_id)
  load_ai_channels(file_path).include?(channel_id.to_s)
end

# Turn AI mode on in a channel. Returns false if it was already on.
def add_ai_channel(file_path, channel_id)
  channel_ids = load_ai_channels(file_path)
  return false if channel_ids.include?(channel_id.to_s)

  save_ai_channels(file_path, channel_ids + [channel_id.to_s])
  true
end

# Turn AI mode off in a channel. Returns false if it was not on there.
def remove_ai_channel(file_path, channel_id)
  channel_ids = load_ai_channels(file_path)
  return false unless channel_ids.include?(channel_id.to_s)

  save_ai_channels(file_path, channel_ids - [channel_id.to_s])
  true
end
