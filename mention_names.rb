# Who a message mentions, and who wrote it, in words the AI can follow.
#
# Discord writes a mention as <@1333324950127378453>. The AI can't tell who that is, so in a busy
# channel it couldn't tell a question for another bot from a question for Cake. (2026-11-11: Piee asked
# the bot Citlali to explain Natlan, then asked Cake "what did I ask you?", and Cake answered as if the
# question and Citlali's reply had been its own.) So mentions are shown as @Name, and other bots get a
# "[bot]" mark after their name. Cake's own messages are never marked: they are the assistant's messages.

BOT_MARK = " [bot]"

# "<@1333> explain" + { "1333" => "Citlali" } => "@Citlali explain". Unknown ids stay as they are.
def name_mentions(text, names)
  text.to_s.gsub(/<@!?(\d+)>/) { names.key?(Regexp.last_match(1)) ? "@#{names[Regexp.last_match(1)]}" : Regexp.last_match(0) }
end

# { "user id" => "name" } for everyone the message mentions.
# A message read from Discord's JSON (discord_history.rb) brings its own names; a normal discordrb
# message has its mentioned users. Anything without a name is left out.
def mentioned_names(message)
  return message.mention_names if message.respond_to?(:mention_names)
  return {} unless message.respond_to?(:mentions)

  message.mentions.to_a.each_with_object({}) do |user, names|
    names[user.id.to_s] = user.display_name if user.respond_to?(:display_name)
  end
end

# The name to show for whoever wrote a message: "Citlali [bot]" for another bot, the plain name for a person
def speaker_label(user)
  bot = user.respond_to?(:bot_account?) && user.bot_account?
  bot ? "#{user.display_name}#{BOT_MARK}" : user.display_name
end
