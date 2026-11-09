# Search a server's memory by MEANING (not by exact words), using embeddings (embeddings.rb).
#
# What can be found: every saved memory (with its id), every person's note (users/<id>.md),
# and every event note, also past events that MEMORY.md no longer shows.
#
# Embedding the same text again would cost money for nothing, so vectors are kept in
# memory/<server_id>/embeddings.json, keyed by a hash of the text. Only new or changed texts are sent.
# That file is not a .md file, so read_memory can never open it.
require 'json'
require 'digest'
require_relative './memory_store'
require_relative './memory_index'
require_relative './embeddings'

EMBEDDING_CACHE_FILE = "embeddings.json"

# The best matches for the query, as text for the AI. Raises on API errors (run_tool catches them).
def search_memory(client, server_id, query)
  chunks, cache = with_server_memory_lock(server_id) { [memory_search_chunks(server_id), read_embedding_cache(server_id)] }
  if chunks.empty?
    with_server_memory_lock(server_id) { File.delete(embedding_cache_path(server_id)) if File.file?(embedding_cache_path(server_id)) }
    return "Nothing is saved in memory for this server yet."
  end

  vectors = vectors_for_chunks(client, chunks, cache)
  query_vector = embed_texts(client, [query]).first
  with_server_memory_lock(server_id) { save_embedding_cache(server_id, chunks, vectors) }

  ranked = chunks.each_index.map { |i| [chunks[i], cosine_similarity(query_vector, vectors[i])] }
  format_memory_matches(query, ranked.max_by(MEMORY_SEARCH_RESULTS) { |_chunk, score| score })
end

# Everything that can be searched: [{ label:, text: }]. Callers hold with_server_memory_lock.
def memory_search_chunks(server_id)
  item_chunks = all_memory_items(server_id).map do |item|
    line = (item[:kind] == :personal ? personal_item_line(item) : general_item_line(item)).delete_prefix("- ")
    { label: line, text: line } # the whole memory fits in its label, so no preview is needed
  end
  item_chunks + personality_chunks(server_id) + event_chunks(server_id)
end

# --- helpers ---

# Only the Personality part of each person's note: their saved facts are already searched one by one above
def personality_chunks(server_id)
  list_memory_files(server_id, "users").filter_map do |path|
    note = read_user_note(server_id, File.basename(path, ".md"))
    next if note.nil? || note[:personality].to_s.strip.empty?

    { label: path, text: "#{path}\n#{note[:name]}: #{note[:description]}\n#{note[:personality]}" }
  end
end

# Every event note, also past events that MEMORY.md no longer shows
def event_chunks(server_id)
  list_memory_files(server_id, "events").filter_map do |path|
    text = read_memory_file(server_id, path)
    { label: path, text: "#{path}\n#{text}" } unless text.to_s.strip.empty?
  end
end

# One vector per chunk. Cached vectors are reused; the rest are embedded in one request.
def vectors_for_chunks(client, chunks, cache)
  keys = chunks.map { |chunk| embedding_key(chunk[:text]) }
  missing = chunks.each_index.reject { |i| cache.key?(keys[i]) }
  new_vectors = embed_texts(client, missing.map { |i| chunks[i][:text][0, EMBEDDING_MAX_CHARS] })
  missing.each_with_index { |chunk_index, n| cache[keys[chunk_index]] = new_vectors[n] }
  keys.map { |key| cache[key] }
end

def embedding_key(text)
  Digest::SHA1.hexdigest(text)
end

def embedding_cache_path(server_id)
  File.join(server_memory_dir(server_id), EMBEDDING_CACHE_FILE)
end

# { hash => vector }. Empty if there is no cache, it is broken, or it was made with another model.
def read_embedding_cache(server_id)
  path = embedding_cache_path(server_id)
  return {} unless File.file?(path)

  data = JSON.parse(File.read(path))
  data["model"] == EMBEDDING_MODEL ? data["vectors"].to_h : {}
rescue JSON::ParserError
  {}
end

# Only the current chunks are kept, so vectors of deleted or changed memories don't pile up
def save_embedding_cache(server_id, chunks, vectors)
  kept = chunks.each_index.to_h { |i| [embedding_key(chunks[i][:text]), vectors[i]] }
  FileUtils.mkdir_p(server_memory_dir(server_id))
  File.write(embedding_cache_path(server_id), JSON.generate({ model: EMBEDDING_MODEL, vectors: kept }))
end

def format_memory_matches(query, ranked)
  lines = ranked.map do |chunk, score|
    preview = one_line(chunk[:text].delete_prefix(chunk[:label]))[0, MEMORY_SEARCH_PREVIEW_CHARS]
    details = preview.empty? || chunk[:label] == chunk[:text] ? "" : " | #{preview}"
    "- (match #{format('%.2f', score)}) #{chunk[:label]}#{details}"
  end
  "Memories closest in meaning to \"#{query}\" (best first; a low match means probably unrelated):\n#{lines.join("\n")}"
end
