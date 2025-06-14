
def initialize_chat_history
  [] # Initialize an empty chat history array
end

def add_message_to_history(history, role, content)
    message = {
        role: role,
        content: content}
    history << message
    return history # Return the updated history each time a message is added.
end

def format_history_for_openai(history)
    formatted_history = []
    i = 0
  while i < history.length
    formatted_history << {
      role: history[i][:role],
      content: history[i][:content]
    }
    i += 1
  end
  return formatted_history # Return the formatted history for OpenAI API
end


def clear_chat_history
    [] # Reset the chat history to an empty array
end