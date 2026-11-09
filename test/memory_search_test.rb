require_relative "test_helper"
require "json"
require_relative "../config"
require_relative "../tool_list"

# Pretends to be OpenAI's Embeddings API. Each text becomes a vector that counts a few topic words,
# so texts about the same topic point the same way (like real embeddings, but predictable).
class FakeEmbeddingClient
  TOPICS = [%w[cat mochi pet], %w[valorant game cup], %w[pho food noodle]].freeze

  attr_reader :embedded

  def initialize
    @embedded = []
  end

  def embeddings(parameters:)
    @embedded.concat(parameters[:input])
    data = parameters[:input].each_with_index.map { |text, i| { "index" => i, "embedding" => fake_vector(text) } }
    { "data" => data.reverse } # OpenAI does not promise the order, so the code must sort by index
  end

  def fake_vector(text)
    words = text.downcase
    TOPICS.map { |topic| topic.sum { |word| words.scan(word).length }.to_f } + [0.1]
  end
end

class MemorySearchTest < Minitest::Test
  def setup
    clear_test_memory
    LOGS.clear
    @client = FakeEmbeddingClient.new
    @ctx = { server_id: 1, requester_id: 123, requester_name: "Bach", channel_id: 555, client: @client }
  end

  def test_cosine_similarity
    assert_in_delta 1.0, cosine_similarity([1, 2], [2, 4])
    assert_in_delta 0.0, cosine_similarity([1, 0], [0, 1])
    assert_in_delta 0.0, cosine_similarity([0, 0], [1, 1])
  end

  def test_finds_the_closest_memory_first
    append_remembered_fact(1, 123, "Bach", "has a pet cat named Mochi")
    append_remembered_fact(1, 123, "Bach", "plays valorant every night")
    result = run_tool("search_memory", '{"query":"what is my cat called"}', @ctx)
    first_match = result.lines[1]
    assert_includes first_match, "Mochi"
  end

  def test_finds_past_events_too
    write_memory_file(1, "events/old-cup.md", "title: Valorant Cup\nwhen: 2020-01-01\n\nBach won the cup")
    result = run_tool("search_memory", '{"query":"who won the valorant game"}', @ctx)
    assert_includes result.lines[1], "events/old-cup.md"
  end

  def test_finds_personality_notes_without_repeating_saved_facts
    change_user_personality(1, 123, "Bach", "Loves cats and talks about Mochi a lot", "cat person")
    append_remembered_fact(1, 123, "Bach", "likes pho")
    chunks = memory_search_chunks(1)
    note_chunk = chunks.find { |chunk| chunk[:label] == "users/123.md" }
    refute_includes note_chunk[:text], "likes pho"
    assert_includes run_tool("search_memory", '{"query":"cat"}', @ctx).lines[1], "users/123.md"
  end

  def test_never_searches_channel_summaries
    write_memory_file(1, "channels/555.md", "secret mod talk about the cat")
    append_remembered_fact(1, 123, "Bach", "likes pho")
    refute_includes run_tool("search_memory", '{"query":"cat"}', @ctx), "secret"
  end

  def test_unchanged_memories_are_not_embedded_again
    append_remembered_fact(1, 123, "Bach", "likes pho")
    run_tool("search_memory", '{"query":"food"}', @ctx)
    first_count = @client.embedded.length
    run_tool("search_memory", '{"query":"food"}', @ctx)
    assert_equal 1, @client.embedded.length - first_count # only the query
  end

  def test_cache_forgets_removed_memories
    append_remembered_fact(1, 123, "Bach", "likes pho")
    run_tool("search_memory", '{"query":"food"}', @ctx)
    remove_memory_item(1, personal_memory_items(1).first)
    run_tool("search_memory", '{"query":"food"}', @ctx)
    refute File.file?(embedding_cache_path(1)) # nothing left to search, so no vectors are kept
  end

  def test_cache_keeps_only_current_memories
    append_remembered_fact(1, 123, "Bach", "likes pho")
    append_remembered_fact(1, 123, "Bach", "has a cat")
    run_tool("search_memory", '{"query":"food"}', @ctx)
    remove_memory_item(1, personal_memory_items(1).first)
    run_tool("search_memory", '{"query":"food"}', @ctx)
    assert_equal 1, JSON.parse(File.read(embedding_cache_path(1)))["vectors"].length
  end

  def test_cache_from_another_model_is_ignored
    append_remembered_fact(1, 123, "Bach", "likes pho")
    File.write(embedding_cache_path(1), JSON.generate({ model: "old-model", vectors: { "x" => [1] } }))
    assert_equal({}, read_embedding_cache(1))
  end

  def test_empty_memory
    assert_includes run_tool("search_memory", '{"query":"cat"}', @ctx), "Nothing is saved"
  end

  def test_empty_query
    assert_includes run_tool("search_memory", '{"query":" "}', @ctx), "Error"
  end

  def test_not_available_without_a_server
    assert_equal MEMORY_NOT_AVAILABLE, run_tool("search_memory", '{"query":"cat"}', @ctx.merge(server_id: nil))
  end

  def test_read_memory_cannot_open_the_cache
    append_remembered_fact(1, 123, "Bach", "likes pho")
    run_tool("search_memory", '{"query":"food"}', @ctx)
    assert_includes run_tool("read_memory", '{"path":"embeddings.json"}', @ctx), "Error"
  end
end
