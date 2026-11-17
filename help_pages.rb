# The pages of !help: the commands grouped into categories, and the embeds and menu that show them.
# !help opens an overview; the dropdown menu (or `!help music`) switches to one category.
# The texts here are what people see in Discord. help_command.rb sends them.
require 'discordrb/webhooks'
require_relative './config'

HELP_COLOR = 0x5DADE2 # light blue, the same as the old single-page !help
HELP_TITLE = "📘 Manual for Cake"
HELP_FOOTER = "Made by Piee"
HELP_OVERVIEW_ID = "overview" # the menu value that goes back to the overview

# Each category: id (used in `!help <id>` and in the menu), emoji, title, and [command, explanation] pairs
HELP_CATEGORIES = [
  { id: "general", emoji: "📌", title: "General", commands: [
    ["🆘 `!help`", "Show this help. `!help music` opens a category directly."],
    ["🏓 `!ping`", "Responds with Pong!"],
    ["🤝 `!invite`", "Get the bot invite link."]
  ] },
  { id: "music", emoji: "🎵", title: "Music", commands: [
    ["🎵 `!play <link or name>`", "Plays music from YouTube, SoundCloud or Spotify in your voice channel (or adds it to the queue)."],
    ["🔊 `!volume [0-100]`", "Sets the volume, or shows it when no number is given. The 🔉 / 🔊 buttons on the panel change it too."],
    ["⏯ `!pause` / `!resume`", "Pauses or resumes the music."],
    ["⏭ `!skip`", "Skips the current song."],
    ["⏩ `!skipplaylist`", "Skips the rest of the current playlist."],
    ["📜 `!queue`", "Shows the songs waiting."],
    ["🗑 `!clearqueue`", "Removes the waiting songs; the current song keeps playing."],
    ["🔁 `!loop [off|song|queue]`", "Repeats the current song or the whole queue. `!loop` alone goes off → song → queue; the Loop button on the panel does it too."],
    ["🔀 `!shuffle`", "Mixes the waiting songs into a random order. The 🔀 button on the panel does it too."],
    ["⏹ `!stop`", "Stops the music and leaves the voice channel (admins can use it from anywhere)."]
  ] },
  { id: "ai", emoji: "🧠", title: "AI & memory", commands: [
    ["🧠 `!neuronactivate`", "Activates AI mode in the current channel (Admin only). Can be on in several channels at once."],
    ["🧠 `!neurondeactivate`", "Deactivates AI mode in the current channel (Admin only)."],
    ["🤫 `!silent [question]`", "Ask Cake privately: your message is deleted and the answer comes in your DMs."],
    ["🧹 `!forgetme`", "Shows what Cake remembers about you; `!forgetme confirm` deletes it all."],
    ["📚 `!buildmemory`", "Reads old messages in every channel and builds a personality note for each person (Admin only)."]
  ] },
  { id: "games", emoji: "🎮", title: "Games", commands: [
    ["🎮 `!wordchain`", "Starts the word chain game."],
    ["🛑 `!wordstop`", "Stops the word chain game."]
  ] },
  # 🛡 needs the emoji variation selector (U+FE0F), or Discord rejects it in the menu and !help fails
  { id: "admin", emoji: "\u{1F6E1}\u{FE0F}", title: "Admin", commands: [
    ["📝 `!badword add [word]`", "Adds a word to the bad words list. (Admin only)"],
    ["🧹 `!badword remove [word]`", "Removes a word from the bad words list. (Admin only)"],
    ["📃 `!badword list`", "Lists all bad words. (Admin only)"],
    ["🧹 `!clear [@user] [amount]`", "Deletes the newest messages here, or only that user's (max #{CLEAR_MAX_MESSAGES}, Admin only)."]
  ] }
].freeze

# Other words people may type after !help, and the category they mean
HELP_ALIASES = { "memory" => "ai", "game" => "games", "mod" => "admin", "moderation" => "admin" }.freeze

# "Music", "memory", "MOD"... => the category id, or nil if the word is not a category
def help_category_id(word)
  word = word.to_s.strip.downcase
  return nil if word.empty?
  return word if help_category(word)

  HELP_ALIASES[word]
end

# The category with this id, or nil
def help_category(id)
  HELP_CATEGORIES.find { |category| category[:id] == id }
end

# The first page: one line per category, with how many commands it has
def help_overview_embed(avatar_url)
  embed = new_help_embed(HELP_TITLE, avatar_url)
  embed.description = "Pick a category below, or type `!help <category>`."
  HELP_CATEGORIES.each do |category|
    count = category[:commands].length
    embed.add_field(name: help_category_name(category), value: "#{count} commands · `!help #{category[:id]}`")
  end
  embed
end

# One category's page: one field per command
def help_category_embed(id, avatar_url)
  category = help_category(id)
  embed = new_help_embed("#{HELP_TITLE} — #{help_category_name(category)}", avatar_url)
  category[:commands].each { |name, text| embed.add_field(name: name, value: text) }
  embed
end

# "🎵 Music"
def help_category_name(category)
  "#{category[:emoji]} #{category[:title]}"
end

# An empty help embed with the usual look (color, avatar, footer, time)
def new_help_embed(title, avatar_url)
  embed = Discordrb::Webhooks::Embed.new(title: title, color: HELP_COLOR, timestamp: Time.now)
  embed.thumbnail = Discordrb::Webhooks::EmbedThumbnail.new(url: avatar_url) if avatar_url
  embed.footer = Discordrb::Webhooks::EmbedFooter.new(text: HELP_FOOTER)
  embed
end

# The dropdown menu under a help page. Its id carries who typed !help ("help:<user_id>"),
# so the bot knows whose menu it is without remembering anything (it still works after a restart).
# selected_id: the page shown now (nil = the overview), marked as the menu's current choice.
def help_menu_view(user_id, selected_id = nil)
  selected_id ||= HELP_OVERVIEW_ID
  Discordrb::Webhooks::View.new do |view|
    view.row do |row|
      row.string_select(custom_id: "help:#{user_id}", placeholder: "Choose a category…") do |menu|
        menu.option(label: "Overview", value: HELP_OVERVIEW_ID, emoji: "📘", default: selected_id == HELP_OVERVIEW_ID)
        HELP_CATEGORIES.each do |category|
          menu.option(label: category[:title], value: category[:id], emoji: category[:emoji],
                      default: selected_id == category[:id])
        end
      end
    end
  end
end
