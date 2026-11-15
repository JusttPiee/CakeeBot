require_relative "test_helper"
require_relative "../config"
require_relative "../help_pages"

class HelpPagesTest < Minitest::Test
  # The commands !help listed before it was split into pages
  OLD_COMMANDS = [
    "!help", "!ping", "!badword add", "!badword remove", "!badword list", "!clear", "!wordchain", "!wordstop",
    "!play", "!pause", "!skip", "!skipplaylist", "!queue", "!clearqueue", "!stop", "!invite",
    "!neuronactivate", "!neurondeactivate", "!buildmemory", "!silent", "!forgetme"
  ].freeze

  def all_command_names
    HELP_CATEGORIES.flat_map { |category| category[:commands].map(&:first) }
  end

  # The select menu inside a view
  def menu_of(view)
    view.to_a.first[:components].first
  end

  def test_every_old_command_is_listed_once
    names = all_command_names
    OLD_COMMANDS.each do |command|
      found = names.count { |name| name.include?("`#{command}`") || name.include?("`#{command} ") }
      assert_equal 1, found, command
    end
  end

  def test_category_order
    assert_equal %w[general music ai games admin], HELP_CATEGORIES.map { |category| category[:id] }
  end

  def test_category_words
    assert_equal "music", help_category_id("Music")
    assert_equal "ai", help_category_id("memory")
    assert_equal "admin", help_category_id("MOD")
    assert_equal "games", help_category_id("game")
    assert_nil help_category_id("pizza")
    assert_nil help_category_id(nil)
    assert_nil help_category_id("")
  end

  def test_overview_lists_every_category
    embed = help_overview_embed("https://a/b.png")
    assert_equal 5, embed.fields.length
    assert_equal "🎵 Music", embed.fields[1].name
    assert_includes embed.fields[1].value, "`!help music`"
    assert_includes embed.fields[1].value, "7 commands"
    assert_equal "📘 Manual for Cake", embed.title
  end

  def test_category_page_has_its_commands
    embed = help_category_embed("games", nil)
    assert_equal "📘 Manual for Cake — 🎮 Games", embed.title
    assert_equal 2, embed.fields.length
  end

  def test_pages_fit_discord_limits
    HELP_CATEGORIES.each do |category|
      embed = help_category_embed(category[:id], nil)
      assert embed.fields.length <= 25
      embed.fields.each { |field| assert field.value.length <= 1024, field.name }
    end
  end

  def test_menu_marks_selected_and_carries_user
    menu = menu_of(help_menu_view(42, "music"))
    assert_equal "help:42", menu[:custom_id]
    assert_equal %w[overview general music ai games admin], menu[:options].map { |option| option[:value] }
    assert menu[:options].find { |option| option[:value] == "music" }[:default]
    refute menu[:options].find { |option| option[:value] == "games" }[:default]
  end

  # Discord rejects a menu emoji like 🛡 unless it has the emoji variation selector (U+FE0F),
  # and then the whole !help message fails to send
  def test_admin_emoji_has_variation_selector
    admin = HELP_CATEGORIES.find { |category| category[:id] == "admin" }
    assert_equal "\u{1F6E1}\u{FE0F}", admin[:emoji]
  end

  def test_menu_without_selection_marks_overview
    menu = menu_of(help_menu_view(42))
    assert menu[:options].find { |option| option[:value] == "overview" }[:default]
  end
end
