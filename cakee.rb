require 'discordrb' # Load Discordrb lib for Discord bot functionality
require 'net/http' # Load required gems
require 'json' # Load required gems
require_relative './ai_config' # Load AI channel ID methods
require_relative './chat_history' # Load chat history methods
require 'openai' # OpenAI lib from https://github.com/alexrudall/ruby-openai
# Set up the bot and OpenAI client
bot = Discordrb::Commands::CommandBot.new token: 'YOUR_BOT_TOKEN', prefix: '!' # Connect to Discord using the bot token with the command prefix '!'
client = OpenAI::Client.new(access_token: "YOUR_OPENAI_KEY") # Initialize OpenAI client with API key








# Main Code starting point
bot_state = {chat_history: initialize_chat_history} # Create an array to store chat history for AI interactions



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
    embed.add_field(name: "🧠 `!neuronactivate`", value: "Activates AI mode in the current channel (Admin only). Can only activate in one channel at a time.")
    embed.add_field(name: "🧠 `!neurondeactivate`", value: "Deactivates AI mode in the current channel (Admin only).")

    embed.footer = Discordrb::Webhooks::EmbedFooter.new(text: "Made by Piee")
    embed.timestamp = Time.now
  end
end

bot.command(:invite) do |event| # Command to get the bot invite link
  invite_url = "YOUR_BOT_INVITE_LINK" # Replace with your bot's invite link
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
    ai_channel_id = load_ai_channel(ai_config_path) # assign the AI channel ID to ai_channel_id variable
    if ai_channel_id && ai_channel_id == event.channel.id.to_s # If AI mode is active in the channel, prevent starting the game
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

ai_config_path = 'ai_config.txt' # Path to the AI channel ID file

bot.command(:neuronactivate) do |event| # turn on AI mode
  if event.user.permission?(:administrator)
    save_ai_channel(ai_config_path, event.channel.id) # Save the channel ID to the file
    bot_state[:chat_history] = clear_chat_history # Clear chat history (in the bot_state variable)
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
    if File.exist?(ai_config_path) # Check if the AI channel ID file exists
      File.delete(ai_config_path) # Delete the file to deactivate AI mode
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
        embed.description = "Neuron Mode is not currently active."
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
  ai_channel_id = load_ai_channel(ai_config_path) # Load the AI channel ID from the file
  return unless ai_channel_id && ai_channel_id == event.channel.id.to_s # Check if the message is in the AI channel, or if AI mode is activated in the channel
  
  prompt = event.message.content.strip # Get the message content
  bot_state[:chat_history] = add_message_to_history(
    bot_state[:chat_history],
    "user",
    prompt
  ) # Add the user's message to the chat history
  event.channel.start_typing # The bot starts typing to simulate a response (discordrb feature)
  messages = format_history_for_openai(bot_state[:chat_history]) # Create a formatted history of the chat messages for OpenAI API
  response = client.chat( # Send a request to the OpenAI API, client was initialized above.
  #these parameters are used to define the model, messages, max tokens, and temperature for the AI response. (From OpenAI API documentation)
    parameters: {
      model: "gpt-4.1-nano-2025-04-14", # Specify the model to use
      messages: messages, # The messages to send to the AI model, which includes the chat history and the user's message
      max_tokens: 600, # Limit the response to 300 tokens (16 - 24 sentences) to avoid vaporizing your and my wallet
      temperature: 0.7 # Set the temperature to 0.7 for a balance between creativity and coherence
    } 
  )

  answer = response.dig("choices", 0, "message", "content") # Extract the AI's response from the API response
  #choices: This is a list of possible responses generated by the AI model. (usually only one choice is returned)
  #0: This is the index of the first choice in the list. (usually only one choice is returned)
  #message: This is the message object that contains the content of the AI's response.
  #content: This is the actual text of the AI's response.
  #dig: This method is used to safely navigate through nested hashes and arrays, returning nil if any key or index is not found.
  bot_state[:chat_history] = add_message_to_history(
    bot_state[:chat_history],
    "assistant",
    answer
  ) # Add the AI's response to the chat history
  
  event.respond(answer || "⚠️ Sorry, I couldn't understand that.") 
  # Respond with the AI's answer or an error message if the response is nil
end

puts "🤖 Cake is alive!"
word_chain_game(bot) #preload the word chain game function
bot.run