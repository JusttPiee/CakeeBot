# Reading far back in a channel. Discord gives at most 100 messages per request, so to read 500
# we ask 5 times, each time for the 100 messages before the oldest one we already have.
# Used by search_channel_history (channel_search.rb) and !buildmemory (build_memory.rb).
#
# Why raw JSON instead of discordrb's channel.history:
# discordrb's message.author looks the author up in the server's member list. For someone who LEFT
# the server, it asks Discord, gets "Unknown Member" (404, printed as an [ERROR] line), and doesn't
# remember the answer, so it asks again for every message of theirs. Discord only allows about
# 2 requests per second, so 500 old messages took minutes. The raw JSON already has the author's name,
# so reading this way never asks Discord anything per message.
#
# Messages are turned into plain hashes, so the rest of the code (and the tests) don't need Discord objects:
#   { id:, author_id:, author_name:, bot:, text:, time: }
require 'json'
require 'time'
require_relative './chat_history'
require_relative './notes_file'

DISCORD_PAGE_SIZE = 100

# A channel to read from: the discordrb channel plus the bot (the raw API needs its token).
# Tests use a fake with the same methods (test/fake_discord.rb).
class ReadingChannel
  attr_reader :id, :name

  def initialize(channel, bot)
    @channel = channel
    @bot = bot
    @id = channel.id
    @name = channel.name
  end

  def server = @channel.server

  # Raw messages (hashes from Discord's JSON), newest first
  def raw_history(amount, before_id = nil, after_id = nil)
    JSON.parse(Discordrb::API::Channel.messages(@bot.token, @id, amount, before_id, after_id))
  end


  # The person's server nickname if discordrb already knows them, or nil. Never asks Discord.
  def cached_nickname(user_id)
    @channel.server&.member(user_id.to_i, false)&.display_name
  rescue StandardError
    nil
  end
end

# Up to `max` raw messages, newest first (the order Discord returns them in).
# Raises if Discord refuses (e.g. no "Read Message History" permission): the caller decides what to do.
def fetch_older_messages(channel, max)
  messages = []
  before_id = nil
  while messages.length < max
    page = channel.raw_history([DISCORD_PAGE_SIZE, max - messages.length].min, before_id)
    messages.concat(page)
    break if page.length < DISCORD_PAGE_SIZE # the start of the channel

    before_id = raw_id(page.last)
  end
  messages
end

# Reading FORWARD from a point in time: up to `max` raw messages sent after after_id, oldest first.
# after_id 0 = from the very first message of the channel.
# Each page is the 100 messages right after the newest one we already have.
def fetch_messages_after(channel, after_id, max)
  messages = []
  while messages.length < max
    page = channel.raw_history([DISCORD_PAGE_SIZE, max - messages.length].min, nil, after_id)
    messages.concat(page)
    break if page.length < DISCORD_PAGE_SIZE # reached the newest message

    after_id = page.map { |message| raw_id(message) }.max
  end
  messages.sort_by { |message| raw_id(message) } # Discord doesn't promise the order inside a page
end

def raw_id(message)
  message["id"].to_i
end

# Every Discord id starts with the time it was made (milliseconds since 2015-01-01, the "Discord epoch").
# So an id for any moment can be calculated, and Discord then gives the messages after that moment.
# This is how the bot can jump straight to a date years ago without reading everything in between.
DISCORD_EPOCH_MS = 1_420_070_400_000

def discord_id_for_time(time)
  milliseconds = (time.to_f * 1000).to_i - DISCORD_EPOCH_MS
  milliseconds.positive? ? milliseconds << 22 : 0
end

# A raw Discord message => a plain hash. Messages with no text (stickers, embeds only) => nil.
def plain_message(raw, channel)
  text = raw["content"].to_s.strip
  return nil if text.empty?

  author = raw["author"] || {}
  { id: raw_id(raw), author_id: author["id"].to_s, author_name: author_name(author, channel),
    bot: author["bot"] == true, text: text, time: Time.parse(raw["timestamp"].to_s) }
end

def plain_messages(channel, raw_messages)
  raw_messages.filter_map { |raw| plain_message(raw, channel) }
end

# Server nickname if known, else their Discord display name, else their username
def author_name(author, channel)
  channel.cached_nickname(author["id"]) || author["global_name"] || author["username"].to_s
end

# "[2026-11-03 14:02] Pie (456): hello", the same format the AI sees in its chat history
def plain_message_line(message, max_chars = nil)
  text = one_line(message[:text])
  text = "#{text[0, max_chars]}..." if max_chars && text.length > max_chars
  "[#{format_timestamp(message[:time])}] #{message[:author_name]} (#{message[:author_id]}): #{text}"
end

# A link that opens the message in Discord, so people can check the evidence themselves
def message_link(server_id, channel_id, message_id)
  "https://discord.com/channels/#{server_id}/#{channel_id}/#{message_id}"
end
