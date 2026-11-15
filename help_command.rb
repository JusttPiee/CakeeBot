# !help and its dropdown menu.
#   !help          shows the overview page with the menu
#   !help music    opens the Music page directly (any category id or alias from help_pages.rb)
# Only the person who typed !help can switch that message's page; anyone else who uses the menu
# gets a private reply. The menu's id is "help:<user_id>", so nothing has to be remembered.
require_relative './help_pages'

HELP_NOT_YOURS_TEXT = "Type `!help` to get your own."

# !help [category]: send the page, with the menu under it. Returns nil (discordrb would post anything else).
def help_command(event, args)
  id = help_category_id(args.first)
  embed = help_page_embed(id, event.bot.profile.avatar_url)
  event.channel.send_message("", false, embed, nil, nil, nil, help_menu_view(event.user.id, id))
  nil
rescue StandardError => e
  log "📘 !help failed (#{e.class}: #{e.message})"
  nil
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
