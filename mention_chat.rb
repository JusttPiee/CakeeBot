# Chat when mentioned: in any channel (not only the !neuronactivate one), Cake answers
# when someone writes @Cake or replies to one of Cake's messages.
# Each time, it reads the channel's recent messages from Discord as context,
# so it needs no memory of its own and still remembers after a restart.
require_relative './channel_reader'
require_relative './channel_lock'
require_relative './ai_chat'
require_relative './message_logger'
require_relative './memory_tidy'
require_relative './discord_history'
require_relative './recent_activity_events' # write each answer into the shared recent memory
require_relative './command_context' # what the command tools (help, music, clear) need
require_relative './thinking_reply' # the "Thinking..." line that becomes the answer

# true if the message @mentions the bot, or is a reply to one of the bot's messages.
# @everyone / @here are not counted: Discord does not put the bot in `mentions` for those.
def mentions_bot?(message, bot_id)
  return true if message.mentions.any? { |user| user.id == bot_id }

  message.reply? && message.referenced_message&.author&.id == bot_id
end

# Discord writes mentions as <@123> (or <@!123>). Show the bot's own mention as "@Name" so it reads naturally.
def name_bot_mentions(history, bot_id, bot_name)
  history.each do |message|
    message[:content] = message[:content].gsub(/<@!?#{bot_id}>/, "@#{bot_name}")
  end
end

# Read the channel, ask the AI, reply to the message that mentioned the bot.
# music: the MusicController (cakee.rb), for the music tool. nil = no music.
# reader is only given by tests; normally the channel is read with a ReadingChannel (discord_history.rb).
def answer_mention(event, client, music = nil, reader = ReadingChannel)
  bot_id = event.bot.profile.id
  bot_name = event.server.bot.display_name # the name the server sees (nickname, or the bot's username)

  with_channel_lock(event.channel.id) do # two quick mentions are answered in order
    reading_channel = reader.new(event.channel, event.bot) # names from the JSON, see discord_history.rb
    history = load_channel_history(reading_channel, bot_id) # already includes the message that mentioned us
    name_bot_mentions(history, bot_id, bot_name)

    context = mention_context(event, music)
    # "<emoji> Thinking...", then edited into the answer, or into the unavailable text (thinking_reply.rb)
    answer, = with_thinking(event) { |thinking| ask_and_deliver(event, thinking, client, history, bot_name, context) }
    unless answer.nil?
      log_bot_reply(event, answer)
      record_recent_answer(event, answer) if context[:command_labels].empty? # a command is not a conversation
      tidy_and_ask(event, client)
    end
  end
end

# Facts from Discord for memory and tools. No channel_id: mention channels have no summary,
# but they still get the server's memory index and the memory tools.
# channel: this channel, so search_channel_history can read back through it (see discord_history.rb).
# The command tools' facts come from command_context (command_context.rb).
def mention_context(event, music = nil)
  { server_id: event.server.id, channel_id: nil, channel: ReadingChannel.new(event.channel, event.bot),
    requester_id: event.author.id, requester_name: event.author.display_name }.merge(command_context(event, music))
end

