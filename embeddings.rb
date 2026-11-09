# OpenAI's Embeddings API: turns a text into a list of numbers (a "vector").
# Texts with a similar MEANING get vectors that point in a similar direction, even if they share no words:
# "what's my cat called?" is close to "has a cat named Mochi".
# Used by search_memory (memory_search.rb). Kept separate so search_channel_history can use it later.
require_relative './config'

# One vector per text, in the same order. One request for the whole list.
# Raises on API errors; the caller decides what to do.
def embed_texts(client, texts)
  return [] if texts.empty?

  response = client.embeddings(parameters: { model: EMBEDDING_MODEL, input: texts })
  response["data"].to_a.sort_by { |item| item["index"] }.map { |item| item["embedding"] }
end

# How close two vectors point: 1.0 = same meaning, around 0 = unrelated
def cosine_similarity(a, b)
  dot = 0.0
  a.each_index { |i| dot += a[i] * b[i] }
  length = vector_length(a) * vector_length(b)
  length.zero? ? 0.0 : dot / length
end

def vector_length(vector)
  Math.sqrt(vector.sum { |value| value * value })
end
