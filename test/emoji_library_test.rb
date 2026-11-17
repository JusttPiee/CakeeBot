require_relative "test_helper"
require_relative "../config"
require_relative "../ai_chat"
require_relative "../emoji_library"

class EmojiLibraryTest < Minitest::Test
  def setup
    FileUtils.rm_f(File.join(MEMORY_DIR, "emoji_notes.json"))
    LOGS.clear
  end

  def lib(path = File.join(MEMORY_DIR, "emoji_notes.json"))
    EmojiLibrary.new(notes_path: path).tap do |l|
      l.refresh(-> { [{ id: 1, name: "sad", animated: false }, { id: 2, name: "dance", animated: true }] })
    end
  end

  def test_conversion_turns_known_names_into_emojis
    assert_equal "so <:sad:1> and <a:dance:2> :nope:", lib.to_discord("so :sad: and :dance: :nope:")
  end

  def test_conversion_leaves_other_colons_alone
    text = "at 10:30:45, see https://x.y/a:b:c and <:sad:1> <a:dance:2>"
    assert_equal text, lib.to_discord(text)
  end

  def test_conversion_leaves_urls_with_known_names_alone
    text = "see https://x.y/:sad:/ and http://a:sad:b"
    assert_equal text, lib.to_discord(text)
  end

  def test_two_emojis_next_to_each_other
    assert_equal "<:sad:1><a:dance:2>", lib.to_discord(":sad::dance:")
  end

  def test_uses_are_counted_and_saved
    l = lib
    l.record_uses(":sad: :sad: :dance: :nope:")
    again = lib
    assert_equal 2, again.entries.find { |e| e.name == "sad" }.uses
  end

  def test_favourites_most_used_first_then_name
    l = lib
    l.record_uses(":sad:")
    assert_equal %w[sad dance], l.favourites(2, now: Time.at(0)).map(&:name)
  end

  def test_favourites_are_cached
    l = lib
    l.record_uses(":sad:")
    l.favourites(2, now: Time.at(0))
    l.record_uses(":dance: :dance:")
    assert_equal %w[sad dance], l.favourites(2, now: Time.at(0) + 10).map(&:name) # still the old list
    assert_equal %w[dance sad], l.favourites(2, now: Time.at(0) + EMOJI_FAVOURITES_REFRESH_SECONDS + 1).map(&:name)
  end

  def test_vanished_emojis_are_dropped_from_notes
    l = lib
    l.set_description(2, "party")
    l.refresh(-> { [{ id: 1, name: "sad", animated: false }] })
    refute_includes File.read(File.join(MEMORY_DIR, "emoji_notes.json")), "party"
  end

  def test_only_missing_descriptions_are_made
    l = lib
    l.set_description(1, "crying")
    asked = []
    l.describe_missing(:client, describer: ->(_c, e) { asked << e.name; "dancing" })
    assert_equal ["dance"], asked
    assert_equal "dancing", l.entries.find { |e| e.name == "dance" }.description
  end

  def test_failed_describer_is_skipped
    l = lib
    l.describe_missing(:client, describer: ->(_c, _e) { raise "openai down" })
    assert_equal 2, l.missing_descriptions.length
    assert(LOGS.any? { |line| line.start_with?("😀 ") })
  end

  def test_empty_description_is_not_stored_and_not_retried
    l = lib
    asked = []
    describer = ->(_c, e) { asked << e.name; "" }
    2.times { l.describe_missing(:client, describer: describer) }
    assert_equal %w[dance sad], asked.sort
    assert_equal 2, l.missing_descriptions.length
  end

  def test_failed_description_is_not_retried_in_the_same_run
    l = lib
    asked = 0
    describer = ->(_c, _e) { asked += 1; raise "openai down" }
    2.times { l.describe_missing(:client, describer: describer) }
    assert_equal 2, asked
  end

  def test_empty_fetch_keeps_old_list_and_notes
    l = lib
    l.set_description(1, "crying")
    l.record_uses(":sad:")
    [[], nil].each { |empty| l.refresh(-> { empty }) }
    sad = l.entries.find { |e| e.name == "sad" }
    assert_equal 2, l.entries.length
    assert_equal "crying", sad.description
    assert_equal 1, sad.uses
    assert(LOGS.any? { |line| line.start_with?("😀 ") })
  end

  def test_empty_fetch_on_first_start_is_fine
    l = EmojiLibrary.new(notes_path: File.join(MEMORY_DIR, "first.json"))
    assert_equal 0, l.refresh(-> { [] })
    assert l.empty?
  end

  def test_failed_refresh_keeps_old_list
    l = lib
    l.refresh(-> { raise "discord down" })
    assert_equal 2, l.entries.length
  end

  def test_empty_library_is_harmless
    l = EmojiLibrary.new(notes_path: File.join(MEMORY_DIR, "e.json"))
    assert l.empty?
    assert_equal "hi :sad:", l.to_discord("hi :sad:")
    assert_equal [], l.favourites(10)
  end

  def test_broken_notes_file_reads_as_empty
    path = File.join(MEMORY_DIR, "broken.json")
    File.write(path, "{not json")
    assert_equal 2, lib(path).entries.length
  end

  # Still no emojis (the first fetch failed): try again soon, not in 30 minutes
  def test_refresh_waits_less_while_the_library_is_empty
    assert_equal EMOJI_RETRY_SECONDS, emoji_refresh_wait(EmojiLibrary.new)
    assert_equal EMOJI_REFRESH_MINUTES * 60, emoji_refresh_wait(lib)
    assert_equal 60, EMOJI_RETRY_SECONDS
  end

  def test_discord_form
    l = lib
    assert_equal "<:sad:1>", l.discord_form("sad")
    assert_equal "<a:dance:2>", l.discord_form("dance")
    assert_nil l.discord_form("nope")
  end

  def test_application_emoji_fetcher_maps_discordrb_emojis
    emoji = Struct.new(:id, :name, :animated?)
    bot = Struct.new(:application_emojis).new([emoji.new(5, "wow", true)])
    assert_equal [{ id: 5, name: "wow", animated: true }], application_emoji_fetcher(bot).call
  end

  def test_describe_emoji_image_asks_with_the_picture
    client = FakeClient.new(answers: ["  sad crying face  "])
    entry = EmojiEntry.new(id: 1, name: "sad")
    text = describe_emoji_image(client, entry, downloader: ->(_url) { "data:image/png;base64,AAAA" })
    assert_equal "sad crying face", text
    part = client.requests.first[:input].first[:content].find { |p| p[:type] == "input_image" }
    assert_equal "data:image/png;base64,AAAA", part[:image_url]
    assert_equal false, client.requests.first[:store]
  end
end
