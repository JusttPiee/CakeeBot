# Writing Discord events into the shared recent memory (recent_activity.rb).
# Kept apart from the chat code: the chat handlers only call these, and a failure here never costs a reply.
require_relative './recent_activity'
require_relative './mention_names' # speaker_label
require_relative './text_attachments' # text_with_attachment_markers
require_relative './ai_config' # ai_channel?

# Write this question and Cake's answer into the server's shared recent memory (recent_activity.rb),
# so Cake knows about it when someone talks to it in another channel. Used by AI channels and mentions.
# A failure here must never cost the reply, so it is only logged.
def record_recent_answer(event, answer)
  record_recent_exchange(event.server.id, recent_channel_info(event.channel), event.author.id,
                         speaker_label(event.author), text_with_attachment_markers(event.message), answer)
rescue StandardError => e
  log "⚠️ Could not write the recent activity (#{e.class})"
end

# --- Tags Cake doesn't answer, for the shared recent memory ---

# true if the text tags the bot (mentions_bot? is in mention_chat.rb, which loads this file). Other bots often send messages with mentions switched off, so Discord leaves
# `mentions` empty although the text still says <@id>. (2026-11-11: Citlali tagged Cake like that.)
def tags_bot?(message, bot_id)
  mentions_bot?(message, bot_id) || message.content.to_s.match?(/<@!?#{bot_id}>/)
end

# Another bot tagged Cake, and nothing will answer it: write one "tagged" line in the shared recent memory,
# so Cake knows about it when someone asks in another channel. Nothing changes about who Cake answers:
# - a person's tag is answered (a mention or an AI channel reply), and that answer is recorded as an exchange
# - a bot tag that Discord counted as a mention is answered by the mention handler, so it isn't noted here
# - in an AI channel every message is answered, so nothing is noted there either
def note_unanswered_tag(event, ai_config_path)
  return unless unanswered_bot_tag?(event, ai_config_path)

  record_recent_tag(event.server.id, recent_channel_info(event.channel), event.author.id,
                    speaker_label(event.author), text_with_attachment_markers(event.message))
rescue StandardError => e
  log "⚠️ Could not write the recent activity (#{e.class})"
end

def unanswered_bot_tag?(event, ai_config_path)
  return false if event.server.nil? || event.message.content.to_s.start_with?('!')

  bot_id = event.bot.profile.id
  return false if event.author.id == bot_id || !(event.author.respond_to?(:bot_account?) && event.author.bot_account?)
  return false unless tags_bot?(event.message, bot_id)

  !mentions_bot?(event.message, bot_id) && !ai_channel?(ai_config_path, event.channel.id)
end
