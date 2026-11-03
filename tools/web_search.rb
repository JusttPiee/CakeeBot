# Tool: search the web with Tavily (https://tavily.com). Free plan: about 1,000 searches a month.
# Only offered to the AI when TAVILY_API_KEY is set in .env (see config.rb).
require 'net/http'
require 'json'
require 'uri'

TAVILY_SEARCH_URL = URI('https://api.tavily.com/search')

# What the AI sees: the tool's name, when to use it, and what to fill in
WEB_SEARCH_DEFINITION = {
  type: "function",
  function: {
    name: "web_search",
    description: "Search the web for current or changing information: weather, news, prices, scores, recent events. " \
                 "Do not use it for things you already know.",
    parameters: {
      type: "object",
      properties: {
        query: { type: "string", description: "What to search for, e.g. \"weather Hanoi today\"" }
      },
      required: ["query"]
    }
  }
}.freeze

def web_search_enabled?
  !TAVILY_API_KEY.nil?
end

# Runs the search and returns the results as text for the AI
def run_web_search(arguments)
  query = arguments["query"].to_s.strip
  return "Error: the search query is empty." if query.empty?

  log "🔎 web_search: #{query}"
  response = send_tavily_search(query)
  return describe_tavily_failure(response) unless response.is_a?(Net::HTTPSuccess)

  format_search_results(JSON.parse(response.body))
end

def send_tavily_search(query)
  request = Net::HTTP::Post.new(TAVILY_SEARCH_URL)
  request['Content-Type'] = 'application/json'
  request['Authorization'] = "Bearer #{TAVILY_API_KEY}"
  request.body = { query: query, max_results: SEARCH_MAX_RESULTS }.to_json

  Net::HTTP.start(TAVILY_SEARCH_URL.host, TAVILY_SEARCH_URL.port, use_ssl: true,
                                                                  open_timeout: 10, read_timeout: 20) do |http|
    http.request(request)
  end
end

# Tell the AI (and the terminal) why the search did not work, so it can answer without it
def describe_tavily_failure(response)
  reason = case response.code
           when '401' then 'the Tavily API key is invalid'
           when '432', '433' then 'the monthly search limit is used up'
           else "Tavily returned HTTP #{response.code}"
           end
  log "⚠️ web_search failed: #{reason}"
  "Search unavailable (#{reason}). Answer from what you already know and say you could not search."
end

# Turn Tavily's JSON into short numbered text: title, link, snippet
def format_search_results(data)
  results = data["results"].to_a
  return "No results found." if results.empty?

  results.each_with_index.map do |result, index|
    "#{index + 1}. #{result['title']}\n#{result['url']}\n#{result['content']}"
  end.join("\n\n")
end
