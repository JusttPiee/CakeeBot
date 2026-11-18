# !help and its dropdown menu.
#   !help          shows the overview page with the menu
#   !help music    opens the Music page directly (any category id or alias from help_pages.rb)
# Only the person who typed !help can switch that message's page; anyone else who uses the menu
# gets a private reply. The menu's id is "help:<user_id>", so nothing has to be remembered.
# The help message deletes itself HELP_CLOSE_AFTER_MINUTES after it was posted, so it does not clutter the chat.
# (A "only you can see this" message is not possible here: Discord only allows that for slash commands
# and menu clicks, and !help is a normal message.)
require_relative './help_pages'

HELP_NOT_YOURS_TEXT = "Type `!help` to get your own."

# Runs the block after `seconds`, in its own thread. Tests pass their own scheduler
HELP_SCHEDULER = lambda do |seconds, &block|
  Thread.new do
    sleep seconds
    block.call
  end
end

# !help [category]: send the page, with the menu under it. Returns nil (discordrb would post anything else).
def help_command(event, args)
  id = help_category_id(args.first)
  post_help_page(event.channel, event.user.id, id, event.bot.profile.avatar_url)
  nil
rescue StandardError => e
  log "📘 !help failed (#{e.class}: #{e.message})"
  nil
end

# Posts a help page with its menu (owner_id = who may switch pages), and deletes it later.
# Used by !help and by the AI's show_help tool.
def post_help_page(channel, owner_id, id, avatar_url, scheduler: HELP_SCHEDULER)
  embed = help_page_embed(id, avatar_url)
  message = channel.send_message("", false, embed, nil, nil, nil, help_menu_view(owner_id, id))
  close_help_later(message, scheduler) if message
  message
end

# Deletes the help message after HELP_CLOSE_AFTER_MINUTES
def close_help_later(message, scheduler)
  scheduler.call(HELP_CLOSE_AFTER_MINUTES * 60) { delete_help_message(message) }
end

# Someone may have deleted it already, so a failure is only logged
def delete_help_message(message)
  message.delete
rescue StandardError => e
  log "📘 could not delete a help message (#{e.class}: #{e.message})"
end

# Someone picked a page in a help menu
def help_menu_selected(event)
  owner = help_menu_owner(event.custom_id)
  return event.respond(content: HELP_NOT_YOURS_TEXT, ephemeral: true) unless owner == event.user.id

  id = help_category_id(event.values.first) # "overview" is not a category, so it gives nil = the overview
  embed = help_page_embed(id, event.bot.profile.avatar_url)
  event.update_message(embeds: [embed], components: help_menu_view(owner, id))
  nil
rescue StandardError => e
  log "📘 help menu failed (#{e.class}: #{e.message})"
  nil
end

# "help:42" => 42 (the person who typed !help). Anything else => nil
def help_menu_owner(custom_id)
  match = custom_id.to_s.match(/\Ahelp:(\d+)\z/)
  match && match[1].to_i
end

# A category's page, or the overview when id is nil
def help_page_embed(id, avatar_url)
  id ? help_category_embed(id, avatar_url) : help_overview_embed(avatar_url)
end
