# Editing a message Cake sent, without pinging anyone.
# Discord pings the person a reply answers again when the reply is edited without allowed_mentions,
# and discordrb's Message#edit sends none. So the "Thinking..." line, sent with mention_user: false,
# would ping when it is edited into the answer. This edit says "ping nobody", like reply!(mention_user: false).
require 'discordrb'

NO_PING_MENTIONS = { replied_user: false }.freeze

module Discordrb
  class Message
    # Changes this message's text and pings nobody. Raises like #edit when Discord refuses
    def edit_without_ping(new_content)
      API::Channel.edit_message(@bot.token, @channel.id, @id, new_content, NO_PING_MENTIONS)
      self
    end
  end
end
