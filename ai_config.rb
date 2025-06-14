# This file contains methods to load and save the AI channel ID to a file.
def load_ai_channel(file_path)
  return nil unless File.exist?(file_path) # Return nil if the file does not exist
  file = File.new(file_path, 'r')
  channel_id = file.gets&.strip # Read the first line and strip whitespace
  file.close
  return channel_id
end

def save_ai_channel(file_path, channel_id) # Save the channel ID to a file
  file = File.new(file_path, 'w') # Create or open the file for writing
  file.puts(channel_id) # Write the channel ID to the file
  file.close
end
