# Tool: open an image someone posted, so the AI can see it. Only called when someone asks about one.
# The AI gives an id from a marker, never a link: only images in the chat history can be opened.
#
# A tool result is text, so the picture goes in a separate user message right after it.
# run_look_at_image queues that message and request_answer (ai_chat.rb) adds it to the next request.
# The picture is only part of this one reply, it never goes in the saved history.
require 'net/http'
require 'uri'
require_relative '../image_attachments'

LOOK_AT_IMAGE_DEFINITION = {
  type: "function",
  name: "look_at_image",
  description: "Look at an image someone posted, using the id from a marker like [image 42: cat.png]. " \
               "Use it only when someone asks about the image or you need to see it to answer. " \
               "Don't use it just because an image was posted.",
  parameters: {
    type: "object",
    properties: {
      image_id: { type: "string", description: "The id from the marker, for example 42" }
    },
    required: ["image_id"]
  }
}.freeze

def run_look_at_image(arguments, context)
  image = context[:images].to_h[arguments["image_id"].to_s.strip]
  return "Error: there is no image with that id in the recent messages." if image.nil?
  return "Error: you can open at most #{IMAGE_MAX_PER_REPLY} images per reply." if context[:image_looks] >= IMAGE_MAX_PER_REPLY

  downloader = context[:image_downloader] || method(:download_image)
  data_url = downloader.call(image[:url])
  return data_url if data_url.start_with?("Error:")

  context[:image_looks] += 1
  context[:pending_images] << image_message(image[:filename], data_url)
  log "🖼️ look_at_image: #{image[:filename]}"
  "The image #{image[:filename]} is in the next message."
end

# The message that shows the picture. 'high' on a picture of at most 1024 pixels is about 1,200 tokens.
def image_message(filename, data_url)
  { role: "user",
    content: [{ type: "input_text", text: "This is the image #{filename}." },
              { type: "input_image", image_url: data_url, detail: "high" }] }
end

# The queued picture messages, for the next request. Each one is only sent once.
def take_pending_images(context)
  pending = context[:pending_images].to_a.dup
  context[:pending_images]&.clear
  pending
end

# Returns the picture as a data url, or an error message for the AI.
# The bot downloads it itself: an expired link is then a tool error, not a failed OpenAI request.
def download_image(url)
  uri = URI.parse(url)
  response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https',
                                                 open_timeout: 10, read_timeout: 20) do |http|
    http.get(uri.request_uri, 'User-Agent' => 'CakeeBot')
  end
  return "Error: the image could not be downloaded (HTTP #{response.code}). The link may have expired." unless response.is_a?(Net::HTTPSuccess)

  image_data_url(response['content-type'], response.body)
end

def image_data_url(content_type, body)
  return "Error: the download is not a supported image (#{content_type})." unless viewable_image_type?(content_type)
  return "Error: the image is too big." if body.bytesize > IMAGE_MAX_BYTES

  type = content_type.split(';').first.strip
  "data:#{type};base64,#{[body].pack('m0')}"
end
