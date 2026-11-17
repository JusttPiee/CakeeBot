# Finding the emojis that fit a feeling or a message, and the emoji parts of the prompt.
# Search is by meaning (embeddings). If embeddings fail, find_emoji falls back to matching words.
require_relative './config'
require_relative './embeddings'
require_relative './emoji_library'

# [id, description] => vector. Kept in RAM only, so just new or changed emojis are embedded.
EMOJI_VECTORS = {}
EMOJI_VECTORS_LOCK = Mutex.new

# ":sad: — crying, :dance: — party" (an emoji without a description is just :name:)
def emoji_line(entries)
  entries.map do |entry|
    entry.description.to_s.empty? ? ":#{entry.name}:" : ":#{entry.name}: — #{entry.description}"
  end.join(", ")
end

# The best `limit` emojis for the query, by meaning. When embeddings fail, by shared words.
def rank_emojis(client, library, query, limit, embedder: method(:embed_texts))
  rank_by_meaning(client, library, query, limit, embedder)
rescue StandardError => e
  log "😀 emoji search by meaning failed (#{e.class}), matching words instead"
  word_match_emojis(library, query, limit)
end

# Raises when the embedder fails
def rank_by_meaning(client, library, query, limit, embedder)
  entries = library.entries
  return [] if entries.empty?

  embed_missing_emojis(client, entries, embedder)
  query_vector = embedder.call(client, [query.to_s]).first
  scored = entries.map { |entry| [cosine_similarity(query_vector, emoji_vector(entry)), entry.name, entry] }
  scored.sort_by { |score, name, _| [-score, name] }.first(limit).map(&:last)
end

def emoji_vector_key(entry)
  [entry.id, entry.description.to_s]
end

def emoji_vector(entry)
  EMOJI_VECTORS_LOCK.synchronize { EMOJI_VECTORS.fetch(emoji_vector_key(entry)) }
end

def emoji_text(entry)
  "#{entry.name}: #{entry.description}"
end

# One embeddings request for the emojis that have no vector yet (none when all are cached)
def embed_missing_emojis(client, entries, embedder)
  missing = EMOJI_VECTORS_LOCK.synchronize { entries.reject { |entry| EMOJI_VECTORS.key?(emoji_vector_key(entry)) } }
  return if missing.empty?

  vectors = embedder.call(client, missing.map { |entry| emoji_text(entry) })
  raise "the embedder returned #{vectors.length} vectors for #{missing.length} emojis" if vectors.length != missing.length
  EMOJI_VECTORS_LOCK.synchronize do
    missing.each_with_index { |entry, i| EMOJI_VECTORS[emoji_vector_key(entry)] = vectors[i] }
  end
end

# Fallback: how many words of the query match the emoji. Most hits first, then by name.
# Words shorter than 3 letters are ignored (they match almost everything).
def word_match_emojis(library, query, limit)
  words = query.to_s.downcase.scan(/[[:alnum:]]+/).uniq.select { |word| word.length >= 3 }
  scored = library.entries.map { |entry| [word_hits(entry, words), entry] }
  scored.select { |hits, _| hits.positive? }.sort_by { |hits, entry| [-hits, entry.name] }.first(limit).map(&:last)
end

# A word hits when it is a whole word of the description or name (names split on "_"), or part of the name
def word_hits(entry, words)
  name = entry.name.downcase
  whole_words = "#{name} #{entry.description.to_s.downcase}".scan(/[[:alnum:]]+/)
  words.count { |word| whole_words.include?(word) || name.include?(word) }
end

# The prompt part that tells Cake about its emojis. "" when there are none.
def emoji_prompt_section(library, count = EMOJI_FAVOURITES)
  return "" if library.empty? || count.to_i <= 0

  "## Your custom emojis\nYou have your own custom emojis. Use them often and playfully, especially to show feelings. " \
    "Write them as :name:. Your favourites: #{emoji_line(library.favourites(count))}. For anything else, call find_emoji."
end

# Emojis that fit the newest message. Never raises: any error means no suggestions (no word fallback here).
def emoji_suggestion_line(client, library, text, count = EMOJI_SUGGESTIONS, embedder: method(:embed_texts))
  return "" if library.empty? || count.to_i <= 0

  found = rank_by_meaning(client, library, text, count, embedder)
  found.empty? ? "" : "Suggested emojis for this message: #{emoji_line(found)}"
rescue StandardError => e
  log "😀 emoji suggestions failed (#{e.class})"
  ""
end
