# Tool: ask to delete recent messages. It only posts a Delete / Cancel question; nothing is deleted
# until the admin presses the button (ai_clear_confirm.rb). Not available in !silent.
require_relative '../ai_clear_confirm'
require_relative '../clear_messages'
require_relative '../command_labels'

MANAGE_MESSAGES_DEFINITION = {
  type: "function",
  name: "manage_messages",
  description: "Ask to delete the newest messages in this channel, or only one person's. Use it when an admin asks " \
               "you to clear or delete messages. It only posts a question with a Delete button; the person must press it. " \
               "Never say messages were deleted; say you asked them to confirm with the button.",
  parameters: {
    type: "object",
    properties: {
      amount: { type: "integer", description: "How many messages, 1 to #{CLEAR_MAX_MESSAGES}" },
      from_user_id: { type: "string", description: "Only delete messages from this user id (digits only), or \"\" for everyone" }
    },
    required: %w[amount from_user_id]
  }
}.freeze

def run_manage_messages(arguments, context)
  return SILENT_COMMAND_TEXT if context[:silent]
  return "Refused: only admins can delete messages." unless context[:member]&.permission?(:administrator)

  amount = arguments["amount"].to_i
  return "Refused: amount must be 1 to #{CLEAR_MAX_MESSAGES}." unless amount.between?(1, CLEAR_MAX_MESSAGES)

  user_id = clear_target_user_id(arguments["from_user_id"])
  return "Refused: from_user_id must be a user id." if user_id == :invalid

  ask_to_confirm_clear(context, amount, user_id)
end

# nil = everyone (also "0", which the AI often writes for "nobody"), a String = that user, :invalid = not an id
def clear_target_user_id(text)
  text = text.to_s.strip
  return nil if text.empty?

  user_id = user_id_from_mention(text)
  return :invalid if user_id.nil?

  user_id.match?(/\A0+\z/) ? nil : user_id
end

def ask_to_confirm_clear(context, amount, user_id)
  requester_id = context[:requester_id]
  post_clear_confirm(context[:post_channel], requester_id, amount, user_id, context[:request_message_id])
  whose = user_id ? " from <@#{user_id}>" : ""
  add_command_label(context, "asked to confirm: delete #{amount} messages#{whose}")
  "Asked <@#{requester_id}> to confirm deleting #{amount} messages#{whose} with a button. " \
    "Nothing is deleted until they press Delete."
end
