# .txt files people post. Discord also turns long messages into a message.txt attachment by itself.
# Like images, the text is NOT sent to the AI right away, because it can be very long.
# The AI only sees a small marker, like "[text file 42: message.txt]", and reads the file
# with the read_text_file tool when it needs to (tools/read_text_file.rb).
require_relative './config'

# The message's text plus a marker for each image and text file. "" if it has none of these.
def text_with_attachment_markers(message)
  [message.content.to_s.strip, image_markers(message), text_file_markers(message)].reject(&:empty?).join(" ")
end

def text_file_markers(message)
  text_file_attachments(message).map { |attachment| "[text file #{attachment.id}: #{attachment.filename}]" }.join(" ")
end

# What read_text_file needs to open each text file of a message
def text_files_from_message(message)
  text_file_attachments(message).map do |attachment|
    { id: attachment.id.to_s, filename: attachment.filename, url: attachment.url }
  end
end

# Every text file in the history, by id: only these can be read, so the AI can't make the bot fetch other links
def text_files_in_history(history)
  files = history.flat_map { |message| message[:text_files].to_a }
  files.to_h { |file| [file[:id], file] }
end

# --- helpers ---

def text_file_attachments(message)
  message.attachments.select { |attachment| !attachment.image? && attachment.filename.to_s.downcase.end_with?(".txt") }
end
