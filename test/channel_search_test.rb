require_relative "test_helper"
require_relative "fake_discord"
require "json"
require_relative "../config"
require_relative "../tool_list"

# Pretends to be OpenAI's Embeddings API: a vector that counts topic words, so texts on the same topic match
class ChannelEmbeddingClient
  TOPICS = [%w[aim noob trash], %w[pho food noodle], %w[valorant cup game]].freeze

  attr_reader :embedded

  def initialize
    @embedded = []
  end

  def embeddings(parameters:)
    @embedded.concat(parameters[:input])
    data = parameters[:input].each_with_index.map { |text, i| { "index" => i, "embedding" => topic_vector(text) } }
    { "data" => data }
  end

  def topic_vector(text)
    TOPICS.map { |topic| topic.sum { |word| text.downcase.scan(word).length }.to_f } + [0.1]
  end
end

class ChannelSearchTest < Minitest::Test
  BACH = HistoryAuthor.new(123, "Bach", false)
  PIE = HistoryAuthor.new(456, "Pie", false)
  CAKE = HistoryAuthor.new(999, "Cake", true)
  START = Time.new(2026, 11, 1, 12, 0)

  def setup
    LOGS.clear
    CHANNEL_EMBEDDINGS.clear
    @client = ChannelEmbeddingClient.new
  end

  def say(id, author, text) = HistoryMessage.new(id, author, text, START + id * 60)

  def context_for(channel)
    { server_id: 1, channel_id: 555, channel: channel, requester_id: 123, requester_name: "Bach",
      client: @client, channel_searches: 0 }
  end

  def search(channel, arguments, context = context_for(channel))
    run_tool("search_channel_history", arguments.to_json, context)
  end

  def argument_set(query: "", contains: "", from_user_id: "", from_date: "")
    { query: query, contains: contains, from_user_id: from_user_id, from_date: from_date }
  end

  # --- reading far back (discord_history.rb) ---

  def test_reads_pages_of_100_until_the_start_of_the_channel
    channel = HistoryChannel.new(history_messages(250, BACH))
    messages = fetch_older_messages(channel, 500)
    assert_equal 250, messages.length
    assert_equal [[100, nil], [100, 151], [100, 51]], channel.requests
    assert_equal 250, raw_id(messages.first) # newest first, like Discord
  end

  def test_never_reads_more_than_the_maximum
    channel = HistoryChannel.new(history_messages(1000, BACH))
    assert_equal 500, fetch_older_messages(channel, 500).length
    assert_equal 5, channel.requests.length
  end

  def test_plain_messages_skip_empty_ones_and_mark_bots
    messages = plain_test_messages([say(1, BACH, "hi"), say(2, CAKE, "hello!"), say(3, PIE, "  ")])
    assert_equal 2, messages.length
    assert_equal({ id: 1, author_id: "123", author_name: "Bach", bot: false, text: "hi", time: START + 60 }, messages[0])
    assert messages[1][:bot]
  end

  # Names come from the raw JSON, so someone who left the server never needs a lookup
  def test_author_names_without_asking_discord
    nicknamed = HistoryAuthor.new(123, "Bach", false, "Boss")
    left_server = HistoryAuthor.new(456, "Pie", false, nil)
    messages = plain_test_messages([say(1, nicknamed, "hi"), say(2, left_server, "yo")])
    assert_equal "Boss", messages[0][:author_name] # the server nickname, when discordrb knows it
    assert_equal "Pie", messages[1][:author_name] # otherwise their Discord name from the message itself
  end

  def test_username_when_there_is_no_display_name
    raw = { "id" => "1", "content" => "hi", "timestamp" => "2022-03-10T12:00:00.000+00:00",
            "author" => { "id" => "456", "username" => "pie_gamer", "global_name" => nil } }
    assert_equal "pie_gamer", plain_message(raw, HistoryChannel.new([]))[:author_name]
  end

  # --- the tool ---

  def test_needs_a_channel
    assert_includes run_tool("search_channel_history", argument_set(query: "x").to_json, { server_id: 1, client: @client }), "not available"
  end

  def test_needs_at_least_one_search_value
    channel = HistoryChannel.new([say(1, PIE, "hi")])
    assert_includes search(channel, argument_set), "at least one"
    assert_empty channel.requests
  end

  def test_finds_messages_by_meaning
    channel = HistoryChannel.new([say(1, PIE, "lunch was pho noodle soup"), say(2, PIE, "Bach your aim is trash, noob"),
                                  say(3, BACH, "valorant cup tonight?")])
    lines = search(channel, argument_set(query: "making fun of someone's aim")).lines.drop(1)
    best = lines.max_by { |line| line[/match ([\d.]+)/, 1].to_f } # lines are oldest first, so find the best score
    assert_includes best, "Pie (456): Bach your aim is trash, noob"
    assert_includes best, "https://discord.com/channels/1/555/2"
  end

  def test_results_are_oldest_first
    channel = HistoryChannel.new([say(1, PIE, "noob aim"), say(2, BACH, "pho"), say(3, PIE, "trash aim again")])
    lines = search(channel, argument_set(from_user_id: "456")).lines.drop(1)
    assert_includes lines[0], "noob aim"
    assert_includes lines[1], "trash aim again"
  end

  def test_filters_by_person_also_from_a_mention
    channel = HistoryChannel.new([say(1, PIE, "from pie"), say(2, BACH, "from bach")])
    result = search(channel, argument_set(from_user_id: "<@456>"))
    assert_includes result, "from pie"
    refute_includes result, "from bach"
  end

  def test_filters_by_exact_text_not_case_sensitive
    channel = HistoryChannel.new([say(1, PIE, "You are a NOOB"), say(2, PIE, "good game")])
    result = search(channel, argument_set(contains: "noob"))
    assert_includes result, "You are a NOOB"
    refute_includes result, "good game"
  end

  def test_says_when_nothing_matched
    channel = HistoryChannel.new([say(1, PIE, "good game")])
    assert_equal "No messages matched in the last 1 messages of this channel (sent 2026-11-01 to 2026-11-01).",
                 search(channel, argument_set(contains: "noob"))
  end

  # --- searching from a date (years back) ---

  def test_discord_ids_contain_their_time
    # A real Discord id, made 2016-04-30 11:18:25.796 UTC
    real_id = 175_928_847_299_117_063
    assert_equal real_id >> 22, discord_id_for_time(Time.at(1_462_015_105.796)) >> 22
    assert_equal 0, discord_id_for_time(Time.at(0)) # before Discord existed = from the very start
  end

  def test_reads_forward_in_pages_of_100
    channel = HistoryChannel.new(history_messages(250, BACH))
    messages = fetch_messages_after(channel, 0, 500)
    assert_equal 250, messages.length
    assert_equal [[100, nil, 0], [100, nil, 100], [100, nil, 200]], channel.requests
    assert_equal 1, raw_id(messages.first) # oldest first
  end

  def test_from_a_month_years_ago
    channel = HistoryChannel.new([dated_message(PIE, "old noob 2021", Time.new(2021, 12, 30)),
                                  dated_message(PIE, "noob in march 2022", Time.new(2022, 3, 10)),
                                  dated_message(PIE, "noob now", Time.new(2026, 11, 9))])
    result = search(channel, argument_set(contains: "noob in march", from_date: "2022-03"))
    assert_includes result, "noob in march 2022"
    assert_includes result, "messages sent from 2022-03 on (sent 2022-03-10 to 2026-11-09)"
    refute_includes result, "2021"
  end

  def test_from_a_date_keeps_the_messages_closest_to_it
    old_times = (1..30).map { |i| Time.new(2022, 3, 1) + i * 3600 }
    channel = HistoryChannel.new(old_times.map { |time| dated_message(PIE, "msg #{time.hour}", time) })
    lines = search(channel, argument_set(from_date: "2022-03-01")).lines.drop(1)
    assert_equal CHANNEL_SEARCH_RESULTS, lines.length
    assert_includes lines.first, "[2022-03-01 01:00]" # the first ones after the date, not the newest
  end

  def test_the_first_messages_of_the_channel
    channel = HistoryChannel.new([dated_message(BACH, "hello, first message!", Time.new(2020, 5, 1)),
                                  dated_message(PIE, "hi", Time.new(2020, 5, 2))])
    result = search(channel, argument_set(from_date: "FIRST"))
    assert_includes result.lines[1], "hello, first message!"
    assert_includes result, "the first 2 messages of this channel"
  end

  def test_rejects_bad_dates
    channel = HistoryChannel.new([say(1, PIE, "hi")])
    assert_includes search(channel, argument_set(from_date: "3 years ago")), "must look like"
    assert_includes search(channel, argument_set(from_date: "2022-13")), "must look like"
    assert_includes search(channel, argument_set(from_date: "2022-02-30")), "must look like"
    assert_empty channel.requests
  end

  def test_valid_dates
    assert valid_search_date?("")
    assert valid_search_date?("first")
    assert valid_search_date?("2022-03")
    assert valid_search_date?("2024-02-29")
    refute valid_search_date?("2023-02-29")
  end

  def test_no_query_means_no_embeddings
    channel = HistoryChannel.new([say(1, PIE, "noob")])
    search(channel, argument_set(contains: "noob"))
    assert_empty @client.embedded
  end

  def test_message_vectors_are_reused
    channel = HistoryChannel.new([say(1, PIE, "noob aim"), say(2, BACH, "pho")])
    search(channel, argument_set(query: "aim"))
    @client.embedded.clear
    search(channel, argument_set(query: "food"))
    assert_equal ["food"], @client.embedded # only the new query, the messages were already embedded
  end

  def test_long_messages_are_cut
    channel = HistoryChannel.new([say(1, PIE, "a" * 1000)])
    result = search(channel, argument_set(from_user_id: "456"))
    assert_includes result, "#{'a' * CHANNEL_SEARCH_MESSAGE_CHARS}..."
    refute_includes result, "a" * (CHANNEL_SEARCH_MESSAGE_CHARS + 1)
  end

  def test_only_a_few_searches_per_reply
    channel = HistoryChannel.new([say(1, PIE, "hi")])
    context = context_for(channel)
    CHANNEL_SEARCHES_PER_REPLY.times { search(channel, argument_set(contains: "hi"), context) }
    assert_includes search(channel, argument_set(contains: "hi"), context), "at most"
  end

  def test_a_discord_error_does_not_crash
    channel = HistoryChannel.new([], error: RuntimeError.new("Missing Access"))
    assert_includes search(channel, argument_set(contains: "hi")), "Error: the search_channel_history tool failed"
  end

  def test_the_tool_is_offered_to_the_ai
    assert_includes tool_definitions.map { |definition| definition[:name] }, "search_channel_history"
  end
end
