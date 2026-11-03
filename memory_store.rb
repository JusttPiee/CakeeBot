# Reading and writing memory files. Each server has its own folder: memory/<server_id>/...
# Paths always come in relative to that folder (e.g. "users/123.md"), and are checked here,
# so nothing (not even the AI through read_memory) can reach a file outside the server's folder.
require 'fileutils'
require_relative './config'

# What the memory tools answer when there is no server to remember things for (e.g. a DM)
MEMORY_NOT_AVAILABLE = "Error: memory is not available here."

# memory/<server_id>
def server_memory_dir(server_id)
  File.join(MEMORY_DIR, server_id.to_s)
end

# The full path for a relative memory path, or nil if the path is not allowed.
# Allowed: plain relative paths to .md files inside the server folder, like "events/cup.md".
def resolve_memory_path(server_id, relative_path)
  path = relative_path.to_s
  return nil unless safe_memory_path?(path)

  dir = File.expand_path(server_memory_dir(server_id))
  full_path = File.expand_path(path, dir)
  full_path.start_with?("#{dir}/") ? full_path : nil
end

# Rules checked before the path is even resolved
def safe_memory_path?(path)
  return false if path.empty? || path.include?("\\") || path.include?("..")
  return false if path.start_with?("/") || path.match?(/\A[a-zA-Z]:/) # absolute paths (Linux or Windows)

  path.end_with?(".md")
end

# The file's text, or nil if the path is not allowed or the file does not exist
def read_memory_file(server_id, relative_path)
  full_path = resolve_memory_path(server_id, relative_path)
  return nil if full_path.nil? || !File.file?(full_path)

  # scrub: a file saved by hand in another encoding gets "?" for bad bytes, instead of crashing every reply
  File.read(full_path, encoding: "UTF-8").scrub("?")
end

# Write a file (creates its folders). Code bugs should be loud, so a bad path raises.
def write_memory_file(server_id, relative_path, text)
  full_path = resolve_memory_path(server_id, relative_path)
  raise ArgumentError, "Not an allowed memory path: #{relative_path}" if full_path.nil?

  FileUtils.mkdir_p(File.dirname(full_path))
  File.write(full_path, text, encoding: "UTF-8")
end

def delete_memory_file(server_id, relative_path)
  full_path = resolve_memory_path(server_id, relative_path)
  File.delete(full_path) if full_path && File.file?(full_path)
end

# The .md files in one folder, as relative paths: ["events/a.md", "events/b.md"]
def list_memory_files(server_id, folder)
  dir = File.join(server_memory_dir(server_id), folder)
  Dir.glob(File.join(dir, "*.md")).map { |file| "#{folder}/#{File.basename(file)}" }.sort
end

# Two channels in the same server can save memory at the same time (compaction, tools).
# One lock per server makes those writes wait their turn. Same idea as channel_lock.rb.
SERVER_MEMORY_LOCKS = {}
SERVER_MEMORY_LOCKS_GUARD = Mutex.new

def with_server_memory_lock(server_id)
  lock = SERVER_MEMORY_LOCKS_GUARD.synchronize { SERVER_MEMORY_LOCKS[server_id.to_s] ||= Mutex.new }
  lock.synchronize { yield }
end
