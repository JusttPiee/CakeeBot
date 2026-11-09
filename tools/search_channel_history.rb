# Tool: read back through older messages of the CURRENT channel, to check what someone really said.
# The channel always comes from the code (context[:channel]), never from the AI, so it can't read other channels.
require_relative '../channel_search'

SEARCH_CHANNEL_HISTORY_DEFINITION = {
  type: "function",
  name: "search_channel_history",
  description: "Search older messages in this channel, further back than your chat history. " \
               "It reads #{CHANNEL_SEARCH_MAX_MESSAGES} messages: the newest ones, or with from_date the ones sent from that date on, " \
               "even years ago. Use it to check what someone really said or did before you believe a claim about it " \
               "(e.g. \"B insulted me last week\"), or when someone asks about an older conversation here. " \
               "The answer says which dates it read; if that doesn't reach far enough, search again with another from_date. " \
               "Give at least one of query, contains, from_user_id or from_date. Use \"\" for the ones you don't need.",
  parameters: {
    type: "object",
    properties: {
      query: { type: "string", description: "What the messages are about, searched by meaning (e.g. \"making fun of Bach's aim\"), or \"\"" },
      contains: { type: "string", description: "Only messages containing this exact text, not case sensitive, or \"\"" },
      from_user_id: { type: "string", description: "Only messages from this user id (digits only), or \"\"" },
      from_date: { type: "string", description: "Read from this date on: YYYY-MM (a month) or YYYY-MM-DD, " \
                                                "\"first\" for the first messages of the channel, or \"\" for the newest messages" }
    },
    required: %w[query contains from_user_id from_date]
  }
}.freeze

def run_search_channel_history(arguments, context)
  return "Error: searching this channel is not available here." if context[:channel].nil? || context[:client].nil?

  search = channel_search_arguments(arguments)
  return "Error: give at least one of query, contains, from_user_id or from_date." if search.values.all?(&:empty?)
  return "Error: from_date must look like 2022-03 or 2022-03-15, or be \"first\"." unless valid_search_date?(search[:from_date])
  return "Error: you can search this channel at most #{CHANNEL_SEARCHES_PER_REPLY} times per reply." if channel_searches_used_up?(context)

  context[:channel_searches] = context[:channel_searches].to_i + 1
  log "🔎 search_channel_history by #{context[:requester_name]} (#{context[:requester_id]}): #{search.inspect}"
  search_channel(context[:client], context[:channel], context[:server_id], search)
end

# --- helpers ---

# Every value is a plain string; a mention like <@456> also works as the user id
def channel_search_arguments(arguments)
  { query: arguments["query"].to_s.strip[0, EMBEDDING_MAX_CHARS],
    contains: arguments["contains"].to_s.strip,
    from_user_id: arguments["from_user_id"].to_s.gsub(/\D/, ""),
    from_date: arguments["from_date"].to_s.strip.downcase }
end

def channel_searches_used_up?(context)
  context[:channel_searches].to_i >= CHANNEL_SEARCHES_PER_REPLY
end
