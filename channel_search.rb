# search_channel_history: find older messages in the CURRENT channel, as evidence.
# Example: A says "B taunted me last week". Instead of just believing A, Cake reads back
# through the channel and quotes what B really wrote, with a link to the message.
#
# One search reads CHANNEL_SEARCH_MAX_MESSAGES messages:
#   - normally the newest ones, going back in time
#   - with from_date ("2022-03", "2022-03-15" or "first"), the ones sent from that date on, going forward.
#     Discord ids contain their time, so the bot jumps straight there, even years back (discord_history.rb).
# Then it:
#   1. keeps only one person's messages, if from_user_id is given
#   2. keeps only messages containing some exact text, if contains is given
#   3. ranks what is left by meaning (embeddings.rb), if query is given;
#      otherwise keeps the newest (normal) or the ones closest to from_date
# Nothing is saved to memory. Message vectors are kept in RAM only, so searching the same channel
# again doesn't pay to embed the same messages twice.
require 'digest'
require 'date'
require_relative './config'
require_relative './discord_history'
require_relative './embeddings'

CHANNEL_EMBEDDINGS = {}
CHANNEL_EMBEDDINGS_LOCK = Mutex.new

SEARCH_FROM_FIRST = "first" # from_date value for "from the very first message of the channel"
SEARCH_DATE_FORMAT = /\A\d{4}-\d{2}(-\d{2})?\z/ # 2022-03 or 2022-03-15

# search = { query:, contains:, from_user_id:, from_date: } (strings, "" when not given)
# from_date must already be checked with valid_search_date?.
# Returns text for the AI. Raises on Discord or OpenAI errors (run_tool catches them).
def search_channel(client, channel, server_id, search)
  messages = read_messages_to_search(channel, search[:from_date])
  searched = searched_text(messages, search[:from_date])
  messages = messages_from(messages, search[:from_user_id])
  messages = messages_containing(messages, search[:contains])
  found = search[:query].empty? ? first_messages(messages) : messages_closest_to(client, messages, search[:query])
  format_channel_matches(found, searched, server_id, channel.id)
end

# --- where to read ---

# "" (newest), "first", "2022-03" or "2022-03-15" (a real date)
def valid_search_date?(text)
  return true if text.empty? || text == SEARCH_FROM_FIRST
  return false unless SEARCH_DATE_FORMAT.match?(text)

  year, month, day = text.split("-").map(&:to_i)
  Date.valid_date?(year, month, day || 1)
end

# The moment to read forward from, or nil to read the newest messages
def search_start_time(from_date)
  return nil if from_date.empty?
  return Time.at(0) if from_date == SEARCH_FROM_FIRST

  year, month, day = from_date.split("-").map(&:to_i)
  Time.new(year, month, day || 1)
end

# Newest first when reading back from now; oldest first when reading forward from a date.
# Either way, the first messages in the list are the ones closest to where the search started.
def read_messages_to_search(channel, from_date)
  start = search_start_time(from_date)
  return plain_messages(channel, fetch_older_messages(channel, CHANNEL_SEARCH_MAX_MESSAGES)) if start.nil?

  plain_messages(channel, fetch_messages_after(channel, discord_id_for_time(start), CHANNEL_SEARCH_MAX_MESSAGES))
end

# Tells the AI what was read, so it knows how far the search reached, e.g.
# "the last 500 messages of this channel (sent 2026-11-01 to 2026-11-10)"
def searched_text(messages, from_date)
  where = case from_date
          when "" then "the last #{messages.length} messages of this channel"
          when SEARCH_FROM_FIRST then "the first #{messages.length} messages of this channel"
          else "#{messages.length} messages sent from #{from_date} on"
          end
  return "#{where} (there are none)" if messages.empty?

  times = messages.map { |message| message[:time] }
  "#{where} (sent #{times.min.strftime('%Y-%m-%d')} to #{times.max.strftime('%Y-%m-%d')})"
end

# --- filters ---

def messages_from(messages, user_id)
  return messages if user_id.empty?

  messages.select { |message| message[:author_id] == user_id }
end

# Not case sensitive: "Noob" finds "noob"
def messages_containing(messages, text)
  return messages if text.empty?

  messages.select { |message| message[:text].downcase.include?(text.downcase) }
end

# [[message, nil], ...]: no score, because nothing was ranked.
# The first ones are the closest to where the search started: the newest, or the closest to from_date.
def first_messages(messages)
  messages.first(CHANNEL_SEARCH_RESULTS).map { |message| [message, nil] }
end

# [[message, score], ...]: the best matches by meaning
def messages_closest_to(client, messages, query)
  return [] if messages.empty?

  vectors = message_vectors(client, messages)
  query_vector = embed_texts(client, [query]).first
  scored = messages.each_index.map { |i| [messages[i], cosine_similarity(query_vector, vectors[i])] }
  scored.max_by(CHANNEL_SEARCH_RESULTS) { |_message, score| score }
end

# --- vectors (cached in RAM) ---

# One vector per message. Only messages not seen before are sent to OpenAI, all in one request.
def message_vectors(client, messages)
  texts = messages.map { |message| message[:text][0, CHANNEL_SEARCH_EMBED_CHARS] }
  missing = texts.uniq.reject { |text| cached_message_vector(text) }
  remember_message_vectors(missing, embed_texts(client, missing))
  texts.map { |text| cached_message_vector(text) }
end

def message_vector_key(text)
  Digest::SHA1.hexdigest("#{EMBEDDING_MODEL}|#{text}")
end

def cached_message_vector(text)
  CHANNEL_EMBEDDINGS_LOCK.synchronize { CHANNEL_EMBEDDINGS[message_vector_key(text)] }
end

# The cache is simply emptied when it gets too big, so the bot's RAM can't keep growing
def remember_message_vectors(texts, vectors)
  CHANNEL_EMBEDDINGS_LOCK.synchronize do
    CHANNEL_EMBEDDINGS.clear if CHANNEL_EMBEDDINGS.length + texts.length > CHANNEL_EMBEDDING_CACHE_MAX
    texts.each_index { |i| CHANNEL_EMBEDDINGS[message_vector_key(texts[i])] = vectors[i] }
  end
end

# --- answer for the AI ---

# Oldest first, so the AI reads them like a conversation
def format_channel_matches(found, searched, server_id, channel_id)
  return "No messages matched in #{searched}." if found.empty?

  lines = found.sort_by { |message, _score| message[:time] }.map do |message, score|
    "- #{match_label(score)}#{plain_message_line(message, CHANNEL_SEARCH_MESSAGE_CHARS)} | #{message_link(server_id, channel_id, message[:id])}"
  end
  "#{matches_intro(found, searched)}\n#{lines.join("\n")}"
end

def match_label(score)
  score ? "(match #{format('%.2f', score)}) " : ""
end

def matches_intro(found, searched)
  intro = "Searched #{searched}. Found #{found.length}, oldest first."
  ranked = !found.first[1].nil?
  intro += " They are ranked by meaning, so a low match means probably unrelated." if ranked
  "#{intro} If you use one as evidence, quote it exactly and add its link:"
end
