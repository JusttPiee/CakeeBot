# Tool: find custom emojis that fit a feeling. The prompt only lists favourites and suggestions; this finds the rest.
require_relative '../emoji_search'

FIND_EMOJI_DEFINITION = {
  type: "function",
  name: "find_emoji",
  description: "Search your custom emojis by meaning. Use it when you want an emoji for a feeling or reaction " \
               "that is not among your favourites or the suggested emojis.",
  parameters: {
    type: "object",
    properties: {
      feeling: { type: "string", description: "The feeling or reaction, in a few words (e.g. \"embarrassed\")" }
    },
    required: ["feeling"]
  }
}.freeze

# context[:emojis] is the library; context[:emoji_searches] counts the searches in this reply.
def run_find_emoji(arguments, context)
  library = context[:emojis]
  return "You have no custom emojis." if library.nil? || library.empty?

  context[:emoji_searches] = context[:emoji_searches].to_i + 1
  return "Error: you can search emojis at most #{EMOJI_SEARCHES_PER_REPLY} times per reply." if context[:emoji_searches] > EMOJI_SEARCHES_PER_REPLY

  feeling = arguments["feeling"].to_s.strip
  embedder = context[:emoji_embedder] || method(:embed_texts) # :emoji_embedder is only set by tests
  found = rank_emojis(context[:client], library, feeling, EMOJI_SEARCH_RESULTS, embedder: embedder)
  "Emojis for \"#{feeling}\": #{emoji_line(found)}"
end
