# Tool: read a .txt file someone posted. Only called when the AI needs what is in it.
# The AI gives an id from a marker, never a link: only files in the chat history can be read.
# The text is only part of this one reply, it never goes in the saved history.
require 'net/http'
require 'uri'
require_relative '../text_attachments'

READ_TEXT_FILE_DEFINITION = {
  type: "function",
  name: "read_text_file",
  description: "Read a text file someone posted, using the id from a marker like [text file 42: message.txt]. " \
               "Discord turns long messages into message.txt, so a marker like that is usually the person's message. " \
               "Read it when someone asks about it or when you need it to answer.",
  parameters: {
    type: "object",
    properties: {
      file_id: { type: "string", description: "The id from the marker, for example 42" }
    },
    required: ["file_id"]
  }
}.freeze

def run_read_text_file(arguments, context)
  file = context[:text_files].to_h[arguments["file_id"].to_s.strip]
  return "Error: there is no text file with that id in the recent messages." if file.nil?
  return "Error: you can read at most #{TEXT_FILE_MAX_PER_REPLY} text files per reply." if context[:text_file_reads] >= TEXT_FILE_MAX_PER_REPLY

  downloader = context[:text_file_downloader] || method(:download_text_file)
  text = downloader.call(file[:url])
  return text if text.start_with?("Error:")

  context[:text_file_reads] += 1
  log "📄 read_text_file by #{context[:requester_name]} (#{context[:requester_id]}): #{file[:filename]} (#{text.length} characters)"
  "Contents of #{file[:filename]}:\n#{text_within_limit(text)}"
end

# A long file is cut, and the AI is told, so it doesn't answer as if it read everything
def text_within_limit(text)
  return text if text.length <= TEXT_FILE_MAX_CHARS

  "#{text[0, TEXT_FILE_MAX_CHARS]}\n[The file was cut here: only the first #{TEXT_FILE_MAX_CHARS} of #{text.length} characters were read.]"
end

# Returns the file's text, or an error message for the AI
def download_text_file(url)
  uri = URI.parse(url)
  response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https',
                                                 open_timeout: 10, read_timeout: 20) do |http|
    http.get(uri.request_uri, 'User-Agent' => 'CakeeBot')
  end
  return "Error: the text file could not be downloaded (HTTP #{response.code}). The link may have expired." unless response.is_a?(Net::HTTPSuccess)

  text_from_download(response.body)
end

def text_from_download(body)
  return "Error: the text file is too big." if body.bytesize > TEXT_FILE_MAX_BYTES
  return "Error: this is not a text file." if body.include?("\0")

  body.dup.force_encoding("UTF-8").scrub.delete_prefix("﻿")
end
