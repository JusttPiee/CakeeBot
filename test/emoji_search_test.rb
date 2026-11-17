require_relative "test_helper"
require_relative "../config"
require_relative "../ai_chat"
require_relative "../emoji_library"
require_relative "../emoji_search"

class EmojiSearchTest < Minitest::Test
  def setup
    EMOJI_VECTORS.clear
    LOGS.clear
  end

  # Vectors from fixed words, so "sad"-ish texts are close to each other
  def fake_embedder = ->(_client, texts) { texts.map { |t| t.include?("sad") || t.include?("cry") ? [1.0, 0.0] : [0.0, 1.0] } }

  # specs look like "name:description"
  def library_with(specs)
    library = EmojiLibrary.new(notes_path: File.join(MEMORY_DIR, "emoji_search_test_notes.json"))
    found = specs.each_with_index.map { |spec, i| { id: i + 1, name: spec.split(":").first, animated: false } }
    library.refresh(-> { found })
    specs.each_with_index { |spec, i| library.set_description(i + 1, spec.split(":", 2).last) }
    library
  end

  def test_rank_puts_closest_first
    ranked = rank_emojis(:client, library_with(%w[sad:crying dance:party]), "I'm sad", 1, embedder: fake_embedder)
    assert_equal ["sad"], ranked.map(&:name)
  end

  def test_vectors_are_cached_by_id_and_description
    calls = 0
    embedder = ->(c, texts) { calls += texts.length; fake_embedder.call(c, texts) }
    lib = library_with(%w[sad:crying dance:party])
    rank_emojis(:client, lib, "x", 1, embedder: embedder)
    rank_emojis(:client, lib, "y", 1, embedder: embedder)
    assert_equal 4, calls # 2 emojis + 1 query, then only 1 query
  end

  def test_find_falls_back_to_words
    broken = ->(*) { raise "api down" }
    assert_equal ["dance"], rank_emojis(:client, library_with(%w[sad:crying dance:party]), "party time", 1, embedder: broken).map(&:name)
  end

  def test_word_fallback_orders_by_hits_then_name
    broken = ->(*) { raise "api down" }
    lib = library_with(%w[b:party\ time a:party c:nothing])
    assert_equal %w[b a], rank_emojis(:client, lib, "party time", 5, embedder: broken).map(&:name)
  end

  def test_emoji_line
    entries = library_with(%w[sad:crying dance:]).entries
    assert_equal ":dance:, :sad: — crying", emoji_line(entries)
  end

  def test_no_emojis_no_section
    assert_equal "", emoji_prompt_section(EmojiLibrary.new(notes_path: File.join(MEMORY_DIR, "x.json")))
  end

  def test_section_text_and_zero_count
    lib = library_with(%w[sad:crying])
    assert_equal "", emoji_prompt_section(lib, 0)
    assert_equal "## Your custom emojis\nYou have your own custom emojis. Use them often and playfully, especially to show feelings. " \
                 "Write them as :name:. Your favourites: :sad: — crying. For anything else, call find_emoji.",
                 emoji_prompt_section(lib, 3)
  end

  def test_suggestion_line
    lib = library_with(%w[sad:crying dance:party])
    line = emoji_suggestion_line(:client, lib, "I'm sad", 1, embedder: fake_embedder)
    assert_equal "Suggested emojis for this message: :sad: — crying", line
  end

  def test_suggestion_line_is_empty_on_error_or_zero_or_empty_library
    lib = library_with(%w[sad:crying])
    assert_equal "", emoji_suggestion_line(:client, lib, "x", 1, embedder: ->(*) { raise "down" })
    assert_equal "", emoji_suggestion_line(:client, lib, "x", 0, embedder: fake_embedder)
    assert_equal "", emoji_suggestion_line(:client, EmojiLibrary.new(notes_path: File.join(MEMORY_DIR, "x.json")), "x", 1, embedder: fake_embedder)
  end

  def test_section_is_before_the_date_and_suggestions_last
    prompt = build_system_prompt("Cake", emoji_section: "## Your custom emojis\nX", emoji_suggestions: "Suggested emojis for this message: :sad:")
    assert prompt.index("## Your custom emojis") < prompt.index("Today's date")
    assert prompt.end_with?("Suggested emojis for this message: :sad:")
  end

  def test_find_emoji_tool_limits_and_formats
    ctx = { emojis: library_with(%w[sad:crying]), client: :client, emoji_searches: 0, emoji_embedder: fake_embedder }
    2.times { assert_match(/\AEmojis for "sad": :sad:/, run_find_emoji({ "feeling" => "sad" }, ctx)) }
    assert_match(/at most 2 times/, run_find_emoji({ "feeling" => "sad" }, ctx))
  end

  def test_find_emoji_without_emojis
    ctx = { emojis: EmojiLibrary.new(notes_path: File.join(MEMORY_DIR, "x.json")), emoji_searches: 0 }
    assert_equal "You have no custom emojis.", run_find_emoji({ "feeling" => "sad" }, ctx)
  end

  def test_find_emoji_is_registered
    assert_includes tool_definitions.map { |d| d[:name] }, "find_emoji"
  end
  def test_word_fallback_ignores_short_words
    broken = ->(*) { raise "api down" }
    lib = library_with(%w[sad:crying dance:party\ time mad:angry\ face imagine:dreaming])
    assert_equal ["sad"], rank_emojis(:client, lib, "I'm sad", 5, embedder: broken).map(&:name)
  end

  def test_short_embedder_result_is_not_cached_and_falls_back
    short = ->(_client, _texts) { [[1.0, 0.0]] } # one vector, whatever was asked
    lib = library_with(%w[sad:crying dance:party])
    assert_equal ["sad"], rank_emojis(:client, lib, "sad", 1, embedder: short).map(&:name)
    assert_empty EMOJI_VECTORS.values.select(&:nil?)
    assert_equal ["sad"], rank_emojis(:client, lib, "sad", 1, embedder: fake_embedder).map(&:name) # works again later
  end

  def test_no_embeddings_call_for_zero_count_or_empty_library
    calls = 0
    counting = ->(c, texts) { calls += 1; fake_embedder.call(c, texts) }
    emoji_suggestion_line(:client, library_with(%w[sad:crying]), "sad", 0, embedder: counting)
    emoji_suggestion_line(:client, EmojiLibrary.new(notes_path: File.join(MEMORY_DIR, "x.json")), "sad", 3, embedder: counting)
    assert_equal 0, calls
  end
end
