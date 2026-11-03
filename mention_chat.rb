# Chat when mentioned: in any channel (not only the !neuronactivate one), Cake answers
# when someone writes @Cake or replies to one of Cake's messages.
# Each time, it reads the channel's recent messages from Discord as context,
# so it needs no memory of its own and still remembers after a restart.
require_relative './channel_reader'
require_relative './channel_lock'
require_relative './ai_chat'

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

# Read the channel, ask the AI, reply to the message that mentioned the bot
def answer_mention(event, client)
  bot_id = event.bot.profile.id
  bot_name = event.server.bot.display_name # the name the server sees (nickname, or the bot's username)

  with_channel_lock(event.channel.id) do # two quick mentions are answered in order
    history = load_channel_history(event.channel, bot_id) # already includes the message that mentioned us
    name_bot_mentions(history, bot_id, bot_name)

    event.channel.start_typing
    answer = ask_ai(client, history, bot_name, mention_context(event))
    if answer.nil? || answer.strip.empty?
      event.message.reply!("⚠️ My AI brain is unavailable right now. Please try again later.", mention_user: false)
    else
      send_reply(event, answer)
    end
  end
end

# Facts from Discord for memory and tools. No channel_id: mention channels have no summary,
# but they still get the server's memory index and the memory tools.
def mention_context(event)
  { server_id: event.server.id, channel_id: nil,
    requester_id: event.author.id, requester_name: event.author.display_name }
end
