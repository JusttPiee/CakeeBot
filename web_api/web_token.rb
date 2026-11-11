# The web UI's secret token. Every API request must send it, so a web page from somewhere else
# (open in the same browser) can't call the API: it doesn't know the token.
# It lives in .env as WEB_UI_TOKEN. The bot creates it the first time, so there is nothing to set up.
# Delete the line in .env to get a new token.
require 'securerandom'

WEB_TOKEN_NAME = "WEB_UI_TOKEN"

def load_or_create_web_token(env_file)
  token = ENV[WEB_TOKEN_NAME].to_s.strip
  return token unless token.empty?

  token = SecureRandom.hex(24)
  save_web_token(env_file, token)
  ENV[WEB_TOKEN_NAME] = token
end

# Fill in an empty "WEB_UI_TOKEN=" line (copied from .env.example), or add the line at the end
def save_web_token(env_file, token)
  text = File.exist?(env_file) ? File.read(env_file) : ""
  empty_line = /^#{WEB_TOKEN_NAME}=[ \t]*$/
  if text.match?(empty_line)
    text = text.sub(empty_line) { "#{WEB_TOKEN_NAME}=#{token}" }
  else
    text += "\n" unless text.empty? || text.end_with?("\n") # don't glue onto an unfinished last line
    text += "#{WEB_TOKEN_NAME}=#{token}\n"
  end
  File.write(env_file, text)
end
