require 'discordrb' # Load Discordrb lib for Discord bot functionality
require 'net/http' # Load required gems
require 'json' # Load required gems
require 'openai' # OpenAI lib from https://github.com/alexrudall/ruby-openai
require 'dotenv' # Load secrets from a .env file into ENV
require 'io/console' # Hide secrets while the user types them

ENV_FILE = File.join(__dir__, '.env') # .env lives next to cakee.rb
ENV_TEMPLATE = File.join(__dir__, '.env.example') # Template listing every setting, with explanations

# Print a timestamped line to the terminal
def log(message)
  puts "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] #{message}"
end

# First run: build .env from .env.example, so every setting (and its explanation) is already in the file
if File.exist?(ENV_FILE)
  log "📄 Found .env at #{ENV_FILE}"
elsif File.exist?(ENV_TEMPLATE)
  File.write(ENV_FILE, File.read(ENV_TEMPLATE))
  log "📄 No .env found, created one from .env.example at #{ENV_FILE}"
else
  log "📄 No .env or .env.example found (will create .env if a key is missing)"
end

# Remember which keys were already set by the OS (e.g. Windows environment variables) BEFORE loading .env.
# Dotenv never overwrites existing variables, so an OS variable silently wins over .env.
OS_ENV_KEYS = ENV.keys.select { |key| !ENV[key].to_s.strip.empty? }
# overwrite: true makes parse return what the FILE says; without it, dotenv swaps in values already set in ENV
DOTENV_VALUES = File.exist?(ENV_FILE) ? Dotenv.parse(ENV_FILE, overwrite: true) : {}
Dotenv.load(ENV_FILE) # Does nothing if the file does not exist

# Our own files come AFTER .env is loaded: they load config.rb, which reads the settings from ENV.
# (Loading them earlier made config.rb see an empty .env, so settings like TAVILY_API_KEY were ignored.)
require_relative './ai_config' # Load AI channel ID methods
require_relative './chat_history' # Per-channel AI memory (add, trim)
require_relative './ai_chat' # Ask OpenAI and send (split) replies
require_relative './channel_lock' # One lock per channel so messages are handled in order
require_relative './channel_reader' # Load recent channel messages when AI mode is turned on
require_relative './message_logger' # Save every received message to logs/messages.log
require_relative './mention_chat' # Answer when @mentioned in any channel
require_relative './ai_channel_chat' # Answer in AI channels, with long-term memory and compaction

# Read a required secret. If it is missing, ask for it once in the terminal and save it to .env,
# so first-time setup is just: run the bot and paste your keys.
def require_env(name, prompt)
  value = ENV[name].to_s.strip
  unless value.empty?
    if OS_ENV_KEYS.include?(name)
      log "🔑 #{name}: loaded from system environment variable"
      log "⚠️ #{name} is also in .env, but the system variable is being used instead" unless DOTENV_VALUES[name].to_s.strip.empty?
    else
      log "🔑 #{name}: loaded from .env"
    end
    return value
  end

  abort "❗ Missing #{name}. Set it as an environment variable or add #{name}=... to #{ENV_FILE}." unless $stdin.tty?

  print "#{prompt} (input is hidden): "
  value = $stdin.noecho(&:gets).to_s.strip
  puts
  abort "❗ #{name} cannot be empty." if value.empty?

  existing = File.exist?(ENV_FILE) ? File.read(ENV_FILE) : ''
  empty_line = /^#{Regexp.escape(name)}=[ \t]*$/ # e.g. "OPENAI_API_KEY=" copied from .env.example
  if existing.match?(empty_line)
    # Fill in the empty line from the template, keeping its comments and position
    File.write(ENV_FILE, existing.sub(empty_line) { "#{name}=#{value}" })
  else
    needs_newline = !existing.empty? && !existing.end_with?("\n") # Don't glue onto an unfinished last line
    File.open(ENV_FILE, 'a') do |file|
      file.puts if needs_newline
      file.puts "#{name}=#{value}"
    end
  end
  log "✅ Saved #{name} to .env"
  ENV[name] = value
end

# Set up the bot and OpenAI client
bot = Discordrb::Commands::CommandBot.new token: require_env('DISCORD_BOT_TOKEN', 'Paste your Discord bot token'), prefix: '!' # Connect to Discord using the bot token with the command prefix '!'

# Check the Discord token once at startup. If it is wrong, discordrb would only log a vague
# "websocket closed" message and stop, so ask Discord directly first and give a clear error.
log "⏳ Checking DISCORD_BOT_TOKEN with Discord..."
begin
  Discordrb::API::User.profile(bot.token)
  log "✅ Discord accepted DISCORD_BOT_TOKEN"
rescue Discordrb::Errors::CodeError, RestClient::Unauthorized => e
  # Only treat "401: Unauthorized" as a bad token; anything else is just a warning
  abort "❗ Discord rejected DISCORD_BOT_TOKEN (invalid token). Fix the DISCORD_BOT_TOKEN line in #{ENV_FILE}, or delete it and run the bot again to re-enter it." if e.message.include?('401')
  log "⚠️ Could not verify DISCORD_BOT_TOKEN right now (#{e.message}). Trying to connect anyway."
rescue StandardError => e
  log "⚠️ Could not verify DISCORD_BOT_TOKEN right now (#{e.class}). Trying to connect anyway."
end

client = OpenAI::Client.new(access_token: require_env('OPENAI_API_KEY', 'Paste your OpenAI API key')) # Initialize OpenAI client with API key

require_relative './config' # All settings (model, reasoning, token cap...) live in config.rb
log "🧠 AI model: #{OPENAI_MODEL}, reasoning: #{OPENAI_REASONING_EFFORT}, max tokens: #{OPENAI_MAX_OUTPUT_TOKENS}#{", temperature: #{OPENAI_TEMPERATURE}" if OPENAI_TEMPERATURE}"
log(TAVILY_API_KEY ? "🔎 Web search: on (Tavily)" : "🔎 Web search: off (add TAVILY_API_KEY to .env to turn it on)")

# Turn an OpenAI/Faraday error into one short line, WITHOUT the request headers (they contain the API key)
def describe_openai_error(error)
  response = error.respond_to?(:response) ? error.response : nil
  status = response.is_a?(Hash) ? response[:status] : nil
  body = response.is_a?(Hash) ? response[:body] : nil
  body = (JSON.parse(body) rescue nil) if body.is_a?(String)
  code = body.is_a?(Hash) ? body.dig('error', 'code') || body.dig('error', 'type') : nil
  reason = body.is_a?(Hash) && status != 401 ? body.dig('error', 'message') : nil # 401 messages quote part of the key, so skip them
  [status && "HTTP #{status}", code, reason && "- #{reason}", ("(#{error.class})" unless status)].compact.join(' ')
end

# Check the OpenAI key once at startup, so a bad key fails now instead of on the first chat message
log "⏳ Checking OPENAI_API_KEY with OpenAI..."
begin
  client.models.list
  log "✅ OpenAI accepted OPENAI_API_KEY"
rescue Faraday::UnauthorizedError
  abort "❗ OpenAI rejected OPENAI_API_KEY (invalid key). Fix the OPENAI_API_KEY line in #{ENV_FILE}, or delete it and run the bot again to re-enter it."
rescue Faraday::Error => e
  log "⚠️ Could not verify OPENAI_API_KEY right now: #{describe_openai_error(e)}. Starting anyway; AI replies may fail."
end








# Main Code starting point
bot_state = {histories: create_history_store} # AI chat memory: one history per channel



# General Commands
bot.command(:help) do |event|
  event.channel.send_embed do |embed|
    embed.title = "📘 Manual for Cake"
    embed.thumbnail = Discordrb::Webhooks::EmbedThumbnail.new(url: event.bot.profile.avatar_url)
    embed.color = 0x5DADE2 # Light blue color
    embed.description = "**Commands:**"

    embed.add_field(name: "🆘 `!help`", value: "Show this help message.")
    embed.add_field(name: "🏓 `!ping`", value: "Responds with Pong!")
    embed.add_field(name: "📝 `!badword add [word]`", value: "Adds a word to the bad words list.(Admin only)")
    embed.add_field(name: "🧹 `!badword remove [word]`", value: "Removes a word from the bad words list.(Admin only)")
    embed.add_field(name: "📃 `!badword list`", value: "Lists all bad words.(Admin only)")
    embed.add_field(name: "🎮 `!play`", value: "Starts the word chain game.")
    embed.add_field(name: "🛑 `!stop`", value: "Stops the word chain game.")
    embed.add_field(name: "🤝 `!invite`", value: "Get the bot invite link.")
    embed.add_field(name: "🧠 `!neuronactivate`", value: "Activates AI mode in the current channel (Admin only). Can be on in several channels at once.")
    embed.add_field(name: "🧠 `!neurondeactivate`", value: "Deactivates AI mode in the current channel (Admin only).")

    embed.footer = Discordrb::Webhooks::EmbedFooter.new(text: "Made by Piee")
    embed.timestamp = Time.now
  end
end

# Permissions requested by the auto-generated invite link (only what the bot actually uses)
BOT_PERMISSIONS = 1024 +  # View Channels
                  2048 +  # Send Messages
                  16384 + # Embed Links (!help, !invite, neuron mode messages)
                  65536   # Read Message History

bot.command(:invite) do |event| # Command to get the bot invite link
  invite_url = ENV['DISCORD_INVITE_URL'].to_s.strip # Custom invite link from .env (optional)
  invite_url = event.bot.invite_url(permission_bits: BOT_PERMISSIONS) if invite_url.empty? # Otherwise let discordrb build one from the bot's client ID
  event.channel.send_embed do |embed|
    embed.title = "🤝 Invite Cake"
    embed.thumbnail = Discordrb::Webhooks::EmbedThumbnail.new(url: event.bot.profile.avatar_url)
    embed.description = "[Click here to invite me to your server!](#{invite_url})"
    embed.color = 0x00FF99
    embed.footer = Discordrb::Webhooks::EmbedFooter.new(text: "Thank you for using Cake!")
    embed.timestamp = Time.now
  end
end
  

bot.command(:ping) do |event| # Command to check if the bot is online
  event.respond "🏓 Pong! <@#{event.user.id}>"
end


# Profanity Filter: Checks for bad words in messages


def load_bad_words(file_path) # Load bad words from file and return them as an array
  # If the file does not exist, create it and return an empty array
  bad_words = [] # Initialize an empty array to store bad words
  if File.exist?(file_path) # Check if the file exists
    file = File.new(file_path, 'r') # If the file exists, open it for reading
    while (line = file.gets) # Read each line from the file
      bad_words << line.strip.downcase unless line.strip.empty? # Add the line to the bad words array, stripping whitespace and converting to lowercase
    end
    file.close
  else
    puts "❗ Warning: Bad words file not found. Creating a new one."
    File.new(file_path, 'w').close # If the file does not exist, create a new file
  end
  return bad_words # Return the array of bad words
end

def append_bad_word_to_file(file_path, word) 
  file = File.new(file_path, 'a')  # add new bad words to the end of the badword text file
  file.puts(word.downcase.strip) # Ensure the word is in lowercase and stripped of whitespace
  puts "✅ Added '#{word}' to the bad words list."
  file.close
end

def overwrite_bad_words_file(file_path, bad_words) #only used when removing all bad words, or when a word is removed.
  file = File.new(file_path, 'w')  # overwrite everything in the file
  i = 0
  while i < bad_words.length # For each bad word in the array
    file.puts(bad_words[i]) # Write the bad word to the file
    i += 1
  end
  file.close
end


def contains_bad_word?(message, bad_words) # Check if the message contains any bad words
  bad_words = load_bad_words('badwords.txt') # Load the bad words from the badwords.txt file
  i = 0
  while i < bad_words.length # For each bad word in the array
    if message.downcase.include?(bad_words[i].downcase) # Check if the message contains the bad word in i position
      return true # If the message contains the bad word, return true
    end
    i += 1
  end
  return false # If no bad words are found in the message, return false
end

bot.message do |event| # Save every message the bot receives (name + user ID) to logs/messages.log
  log_received_message(event)
end

bot.message do |event| #checks for bad words in messages (triggers on every message)
  bad_words = load_bad_words('badwords.txt') # Load the bad words from the badwords.txt file
  warning_message = "Don't use bad words! <@#{event.user.id}>" # Warning message to send if a bad word is found and mention the user who sent the message
  if event.message.content.start_with?('!') # Ignore checking when prefix is used
    next
  end

  if contains_bad_word?(event.message.content, bad_words) # Call the contains_bad_word? function to check true or false
    event.respond warning_message # Respond with a warning message when true
  end
end

bot.command(:badword) do |event, action, *args| # Command to manage bad words (add, remove, list) (admin only)
  file_path = 'badwords.txt' # Path to the bad words file
  bad_words = load_bad_words('badwords.txt') # Load the bad words from the badwords.txt file, return array
  if event.user.permission?(:administrator) 
    # Only allow admins to use the badword command
  else
    event.channel.send_embed do |embed| # Send an embed message if the user is not an admin
      embed.title = "⛔ Permission Denied"
      embed.description = "You do not have permission to use this command."
      embed.color = 0xE74C3C # Red
      embed.timestamp = Time.now
    end
    next
  end

  if action.nil? # If no action is provided, show the usage instructions
    event.channel.send_embed do |embed|
      embed.title = "📝 Badword Command Usage"
      embed.description = "Usage:\n`!badword add [word]`\n`!badword remove [word]`\n`!badword list`"
      embed.color = 0xE67E22 # Orange color
      embed.footer = Discordrb::Webhooks::EmbedFooter.new(text: "Made by Piee")
      embed.timestamp = Time.now
    end
    next
  end

  if action == 'add' # If the action is 'add', add a new bad word to the list
    word = args.join(" ").strip.downcase # extract the word from the arguments
    if word.strip.empty? # If no word is provided, show an error message
      event.respond "❗ Please enter a word to add to list."
      elsif bad_words.include?(word.downcase) # If the word is already in the list, show an error message
        event.respond "❗ The word '#{word}' is already in the list."
      else
        append_bad_word_to_file(file_path, word) # If the word is not in the list, add it to the file, calling the append_bad_word_to_file function
        bad_words << word.downcase # Add the word to the bad_words array
        event.respond "✅ Added '#{word}' into the list and save in file."
    end
  
  elsif action == 'remove' # If the action is 'remove', remove a bad word from the list
    word_to_remove = args.join(" ").strip.downcase # extract the word from the arguments
    found = false # Flag to check if the word was found in the list
    i = 0
    while i < bad_words.length # Loop through the bad words array
      if bad_words[i] == word_to_remove
        bad_words.delete_at(i) # If the word is found, remove it from the array
        found = true # Set the found flag to true
      break # Break the loop after removing the word
    end
    i += 1
    end

    if found # If the word was found and removed
      overwrite_bad_words_file(file_path, bad_words)
      event.respond "✅ Removed '#{word_to_remove}' from the list." # Respond with a success message
      else
      event.respond "❗ The word '#{word_to_remove}' does not exist in the list." # If the word was not found, respond with an error message
  end
  
  elsif action == 'list' # If the action is 'list', show the list of bad words
    if bad_words.empty? # If the bad words list is empty, respond with a message indicating that there are no bad words
      event.respond "📭 No badwords found."
    else
      i = 0
      badword_list =  []
      while i < bad_words.length # Loop through the bad words array
        word = bad_words[i] # Get the bad word at index i
        line = "#{i + 1}. #{word}" # Create a formatted string with the index and the word
        badword_list << line # Add the formatted string to the badword_list array
        i += 1
      end
      event.respond "📜 Badwords list:\n" + badword_list.join("\n") # After finish looping through the bad words array, respond with the list of bad words
    end
  else
    event.respond "❓Invalid command '#{action}'." # If the action is not recognized, respond with an error message
  end
end


# Word Chain Game

def valid_word?(word) # Checks if the word is a valid English word using an external API
  url = URI("https://api.dictionaryapi.dev/api/v2/entries/en/#{word.downcase}") # API endpoint to check if the word is valid
  # The API returns a 200 status code if the word is valid, otherwise it returns an error code
  response = Net::HTTP.get_response(url) # Send a GET request to the API endpoint

  if response.code == "200" # If the response code is 200, the word is valid and return true
    return true 
  else
    return false # If the response code is not 200, the word is not valid and return false
  end
end

def word_chain_game(bot) #Code for the word chain game
  #General variables for the game
  game_active = false
  used_words = []
  last_letter = nil
  last_user_id = nil
  wrong_attempts = 0
  bot.command(:play) do |event| #Starts the game
    ai_config_path = 'ai_config.txt' # Path to the AI channel ID file
    if ai_channel?(ai_config_path, event.channel.id) # If AI mode is active in the channel, prevent starting the game
      event.respond "⚠️ Neuron mode is currently active in this channel. Please deactivate it using `!neurondeactivate` before playing the game." # Send a warning message if AI mode is active
      next
    end
    if game_active # If a game is already active, prevent starting a new game
      event.respond "🎮 A game is already in progress. Please wait for it to finish."
      else # If no game is active, set game_active to true, clearing the used words, last letter, last user ID, and wrong attempts
        game_active = true 
        used_words.clear
        last_letter = nil
        last_user_id = nil
        event.respond "🎮 Word chain game started! The first player can start with any word."
      end
    end

  bot.command(:stop) do |event| # Command to stop the game
    if game_active # If a game is active, set game_active to false and respond with a message
      game_active = false
      event.respond "🛑 Word chain game stopped."
    else # If no game is active, respond with a message indicating that there is no active game
      event.respond "❗ No active game to stop."
    end
  end
  
  bot.message do |event| # Message event to handle word submissions
    next unless game_active # Always skip if the game is not active
    next if event.message.content.start_with?('!') # Always skip if the message starts with '!' (command prefix)
    word = event.message.content.strip.downcase # Get the word from user message, stripping whitespace and converting to lowercase
    if event.user.id == last_user_id # If the user is the same as the last user who submitted a word, skip the message
      event.respond "❗ It's not your turn! Wait for the next player."
      next
    end

    if !valid_word?(word) # Check if the word is a valid English word using the valid_word? function
      wrong_attempts += 1 # Increment the wrong attempts counter if the word is not valid, and respond with an error message
      event.respond "❗ The word '#{word}' is not valid. Please use a valid English word."
      event.respond "❌ Wrong attempts: #{wrong_attempts}/3"
      if wrong_attempts >= 3 # If the wrong attempts reach 3, end the game and declare the last user as the winner
        game_active = false # Set game_active to false to end the game
        event.respond "🏁 Game over! The winner is <@#{last_user_id}> 🎉"
      end
      next
    end

    if used_words.include?(word) # Check if the word has already been used in the game
      wrong_attempts += 1
      event.respond "❗ The word '#{word}' has already been used. Please use a different word."
      event.respond "❌ Wrong attempts: #{wrong_attempts}/3"
      if wrong_attempts >= 3
        game_active = false
        event.respond "🏁 Game over! The winner is <@#{last_user_id}> 🎉"
      end
      next
    end

    if last_letter && word[0] != last_letter # Check if the word starts with the last letter of the previous word
      wrong_attempts += 1
      event.respond "❗ The word '#{word}' does not start with the letter '#{last_letter}'. Please use a word that starts with this letter."
      event.respond "❌ Wrong attempts: #{wrong_attempts}/3"
      if wrong_attempts >= 3
        game_active = false
        event.respond "🏁 Game over! The winner is <@#{last_user_id}> 🎉"
      end
      next
    end

    used_words << word # Add the word to the used words list
    last_letter = word[-1] # Get the last letter of the word
    last_user_id = event.user.id # Set the last user ID to the current user's ID
    # Respond with a success message, indicating the next player should use a word that starts with the last letter of the current word
    event.respond "✅ The word '#{word}' has been accepted. The next player should use a word that starts with '#{last_letter}'."
  end
end

# AI functionality

ai_config_path = 'ai_config.txt' # AI channel IDs, one per line (AI mode can be on in several channels)

bot.command(:neuronactivate) do |event| # turn on AI mode
  if event.user.permission?(:administrator)
    add_ai_channel(ai_config_path, event.channel.id) # Add this channel to the saved list (other AI channels stay on)
    log "🧠 AI mode turned on in #{describe_message_place(event)}"
    with_channel_lock(event.channel.id) do # Start this channel's AI memory from its recent messages
      bot_state[:histories][event.channel.id] = load_ai_channel_history(event.channel, event.bot.profile.id)
    end
    event.channel.send_embed do |embed| # Send an embed message to confirm activation of AI mode
      embed.title = "🧠 Neuron Mode Activated"
      embed.description = "Neuron Mode has been **activated** for this channel!"
      embed.color = 0x27AE60 # Green
      embed.footer = Discordrb::Webhooks::EmbedFooter.new(text: "AI mode enabled by #{event.user.name}")
      embed.timestamp = Time.now
    end
  else
    event.channel.send_embed do |embed| # Send an embed message if the user is not an admin
      embed.title = "⛔ Permission Denied"
      embed.description = "Only admins can activate neuron mode!"
      embed.color = 0xE74C3C # Red
      embed.timestamp = Time.now
    end
  end
end

bot.command(:neurondeactivate) do |event| # turn off AI mode
  if event.user.permission?(:administrator)
    if remove_ai_channel(ai_config_path, event.channel.id) # Only this channel; other AI channels stay on
      bot_state[:histories].delete(event.channel.id) # Free this channel's memory
      log "🧠 AI mode turned off in #{describe_message_place(event)}"
      event.channel.send_embed do |embed|
        embed.title = "🧠 Neuron Mode Deactivated"
        embed.description = "Neuron Mode has been **deactivated** for this channel!"
        embed.color = 0x95A5A6 # Gray
        embed.footer = Discordrb::Webhooks::EmbedFooter.new(text: "AI mode disabled by #{event.user.name}")
        embed.timestamp = Time.now
      end
    else
      event.channel.send_embed do |embed| # Send an embed message if AI mode is not active
        embed.title = "⚠️ Neuron Mode Not Active"
        embed.description = "Neuron Mode is not active in this channel."
        embed.color = 0xF1C40F # Yellow
        embed.timestamp = Time.now
      end
    end
  else
    event.channel.send_embed do |embed| # Send an embed message if the user is not an admin
      embed.title = "⛔ Permission Denied"
      embed.description = "Only admins can deactivate neuron mode!"
      embed.color = 0xE74C3C # Red
      embed.timestamp = Time.now
    end
  end
end



bot.message do |event| # Message event to handle AI interactions
  next if event.message.content.start_with?('!') #skip if prefix detected
  next unless ai_channel?(ai_config_path, event.channel.id) # Only answer every message in AI channels

  with_channel_lock(event.channel.id) do # Handle this channel's messages one at a time
    answer_ai_channel_message(event, client, bot_state[:histories][event.channel.id]) # see ai_channel_chat.rb
  end
end

bot.message do |event| # Answer when @mentioned (or replied to) in any other channel
  next if event.server.nil? # DMs: not handled yet
  next if event.message.content.start_with?('!') # commands are handled by bot.command
  next if event.author.id == event.bot.profile.id # never answer ourselves
  next unless mentions_bot?(event.message, event.bot.profile.id)
  next if ai_channel?(ai_config_path, event.channel.id) # AI channels already answer everything

  answer_mention(event, client)
end

word_chain_game(bot) #preload the word chain game function

# Only announce we're alive once Discord has actually accepted the token and connected
bot.ready do |event|
  log "🤖 Cake is alive! Logged in as #{event.bot.profile.distinct} in #{event.bot.servers.size} server(s)"
  restore_ai_memory(event.bot, bot_state[:histories], load_ai_channels(ai_config_path)) # remember the AI chats after a restart
end

bot.disconnected do
  log "🔌 Disconnected from Discord (it will try to reconnect automatically)"
end

log "⏳ Connecting to Discord..."
bot.run
log "🛑 Bot stopped." # bot.run only returns if Discord closed the connection for good