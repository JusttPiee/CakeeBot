# Tool: open a web page and give the AI its plain text (for links people paste in the chat).
# Local and private network addresses (localhost, 192.168.x.x...) are blocked, so the bot
# can't be used to peek inside the computer or network it runs on.
require 'net/http'
require 'uri'
require 'ipaddr'
require 'resolv'
require 'cgi'

MAX_REDIRECTS = 3

READ_WEBPAGE_DEFINITION = {
  type: "function",
  name: "read_webpage",
  description: "Open a web page (http or https link) and read its text. Use it when someone shares a link, " \
               "or to read a page found with web_search.",
  parameters: {
    type: "object",
    properties: {
      url: { type: "string", description: "The full link, starting with http:// or https://" }
    },
    required: ["url"]
  }
}.freeze

# Returns the page text (cut to WEBPAGE_MAX_CHARS), or an error message for the AI
def run_read_webpage(arguments, _context = {})
  url = arguments["url"].to_s.strip
  log "🌐 read_webpage: #{url}"
  response = fetch_page(url)
  return response if response.is_a?(String) # an error message

  page_to_text(response)
end

# Follows a few redirects, and checks every address before connecting to it
def fetch_page(url, redirects_left = MAX_REDIRECTS)
  uri = URI.parse(url)
  problem = check_url(uri)
  return problem if problem

  response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https',
                                                 open_timeout: 10, read_timeout: 20) do |http|
    http.get(uri.request_uri, 'User-Agent' => 'CakeeBot')
  end
  return response unless response.is_a?(Net::HTTPRedirection)
  return "Error: too many redirects." if redirects_left.zero?

  fetch_page(URI.join(uri, response['location']).to_s, redirects_left - 1)
rescue URI::InvalidURIError
  "Error: that is not a valid link."
end

# Returns an error message if the link is not allowed, or nil if it is fine
def check_url(uri)
  return "Error: only http and https links can be opened." unless %w[http https].include?(uri.scheme)
  return "Error: the link has no website name." if uri.host.to_s.empty?
  return "Error: local and private network addresses are blocked." if private_address?(uri.host)

  nil
end

# true if the host is (or points to) this computer or a private network
def private_address?(host)
  addresses = Resolv.getaddresses(host)
  return true if addresses.empty? # unknown host: don't risk it

  addresses.any? do |address|
    ip = IPAddr.new(address)
    ip.loopback? || ip.private? || ip.link_local? || address == '0.0.0.0' || address == '::'
  end
end

def page_to_text(response)
  return "Error: the page returned HTTP #{response.code}." unless response.is_a?(Net::HTTPSuccess)

  type = response['content-type'].to_s
  return "Error: this link is not a text page (#{type})." unless type.include?('text/')

  body = response.body.to_s.dup.force_encoding('UTF-8').scrub('')
  text = type.include?('html') ? html_to_text(body) : body
  text = text.strip
  return "The page has no readable text." if text.empty?

  text.length > WEBPAGE_MAX_CHARS ? "#{text[0, WEBPAGE_MAX_CHARS]}\n[...page cut off]" : text
end

# Very simple HTML cleanup: drop scripts and styles, drop tags, squash spaces
def html_to_text(html)
  text = html.gsub(%r{<(script|style|noscript)[^>]*>.*?</\1>}mi, ' ')
  text = text.gsub(/<[^>]+>/, ' ')
  CGI.unescapeHTML(text).gsub(/[ \t\r\f]+/, ' ').gsub(/\s*\n\s*/, "\n")
end
