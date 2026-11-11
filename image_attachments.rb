# Images people post in Discord. The picture is NOT sent to the AI right away, because images cost money.
# The AI only sees a small marker in the text, like "[image 42: cat.png]", and opens the picture
# with the look_at_image tool when someone asks about it (tools/look_at_image.rb).
require_relative './config'
require_relative './text_attachments'

VIEWABLE_IMAGE_TYPES = %w[image/png image/jpeg image/webp].freeze

def viewable_image_type?(content_type)
  VIEWABLE_IMAGE_TYPES.include?(content_type.to_s.split(';').first.to_s.strip)
end

# "[image 42: cat.png] [dance.gif: this image type can't be viewed]". Other files get no marker here.
def image_markers(message)
  images = message.attachments.select(&:image?)
  images.map { |attachment| image_marker(attachment) }.join(" ")
end

def image_marker(attachment)
  return "[image #{attachment.id}: #{attachment.filename}]" if viewable_image_type?(attachment.content_type)

  "[#{attachment.filename}: this image type can't be viewed]"
end

# What look_at_image needs to open each viewable image of a message
def images_from_message(message)
  viewable = message.attachments.select { |item| item.image? && viewable_image_type?(item.content_type) }
  viewable.map do |attachment|
    { id: attachment.id.to_s, filename: attachment.filename,
      url: resized_image_url(attachment.proxy_url || attachment.url, attachment.width, attachment.height) }
  end
end

# Discord's image server can scale pictures: ...?width=1024&height=512.
# Smaller pictures cost fewer tokens. Pictures that already fit keep their url.
def resized_image_url(url, width, height)
  longest_side = [width, height].max
  return url if longest_side <= IMAGE_MAX_SIDE

  new_width = width * IMAGE_MAX_SIDE / longest_side
  new_height = height * IMAGE_MAX_SIDE / longest_side
  base = url.chomp('&')
  "#{base}#{base.include?('?') ? '&' : '?'}width=#{new_width}&height=#{new_height}"
end

# Every image in the history, by id: only these can be opened, so the AI can't make the bot fetch other links
def images_in_history(history)
  images = history.flat_map { |message| message[:images].to_a }
  images.to_h { |image| [image[:id], image] }
end

# When someone replies to a message, the AI must know whose message it was, or it thinks
# everything belongs to the person asking. Images and text files in that message can be opened too.
# history_entry is the reply in the history, message is the reply from Discord.
# reply? is only true when Discord sent the replied message along, so this makes no extra Discord request.
def add_reply_note(history_entry, message)
  return if history_entry.nil? || !message.reply?

  replied = message.referenced_message
  return if replied.nil?

  history_entry[:content] += " #{reply_note(replied)}"
  history_entry[:images] = history_entry[:images].to_a + images_from_message(replied)
  history_entry[:text_files] = history_entry[:text_files].to_a + text_files_from_message(replied)
rescue StandardError => e
  log "⚠️ Could not read the replied message (#{e.class})." # the reply still works without the note
end

# "(replying to b (777): gg ez [image 42: cat.png])"
def reply_note(replied)
  parts = [short_quote(name_mentions(replied.content, mentioned_names(replied))), image_markers(replied), text_file_markers(replied)].reject(&:empty?)
  "(replying to #{replied.author.display_name} (#{replied.author.id}): #{parts.join(' ')})"
end

def short_quote(text)
  one_line = text.to_s.strip.gsub(/\s+/, ' ')
  one_line.length > REPLY_QUOTE_MAX_CHARS ? "#{one_line[0, REPLY_QUOTE_MAX_CHARS]}..." : one_line
end
