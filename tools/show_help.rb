# Tool: show a !help page in the channel, with its menu. Not available in !silent.
require_relative '../help_command'
require_relative '../command_labels'

SHOW_HELP_DEFINITION = {
  type: "function",
  name: "show_help",
  description: "Show Cake's help page (the command list with a menu) in this channel. Use it when someone asks " \
               "what you can do, what the commands are, or how to use a command. " \
               "Pick the category that fits, or overview when unsure.",
  parameters: {
    type: "object",
    properties: {
      category: { type: "string", enum: [HELP_OVERVIEW_ID, *HELP_CATEGORIES.map { |category| category[:id] }],
                  description: "Which help page to show" }
    },
    required: ["category"]
  }
}.freeze

def run_show_help(arguments, context)
  return SILENT_COMMAND_TEXT if context[:silent]

  id = help_category_id(arguments["category"])
  title = id ? help_category(id)[:title] : "Overview"
  embed = help_page_embed(id, context[:avatar_url])
  context[:post_channel].send_message("", false, embed, nil, nil, nil, help_menu_view(context[:requester_id], id))
  add_command_label(context, "showed help: #{title}")
  "Showed the help page #{title}."
end
