require_relative "test_helper"
require_relative "../mention_names"

# Discord writes a mention as <@id>. The AI can't tell who that is, so mentions are shown by name,
# and other bots are marked, so Cake doesn't mix up what was said to (or by) another bot with its own chat.
class MentionNamesTest < Minitest::Test
  # Like a discordrb User: display_name, and bot_account? for bots
  class FakeUser
    attr_reader :id, :display_name

    def initialize(id, display_name, bot: false)
      @id = id
      @display_name = display_name
      @bot = bot
    end

    def bot_account? = @bot
  end

  FakeMessage = Struct.new(:content, :mentions)

  def test_known_mentions_become_names
    names = { "1333" => "Citlali", "456" => "Pie" }
    assert_equal "@Citlali ask @Pie", name_mentions("<@1333> ask <@!456>", names)
  end

  def test_an_unknown_mention_stays_as_it_is
    assert_equal "hi <@789>", name_mentions("hi <@789>", { "1333" => "Citlali" })
  end

  def test_names_come_from_the_users_a_discordrb_message_mentions
    message = FakeMessage.new("<@1333> hi", [FakeUser.new(1333, "Citlali", bot: true), FakeUser.new(456, "Pie")])
    assert_equal({ "1333" => "Citlali", "456" => "Pie" }, mentioned_names(message))
  end

  def test_a_message_from_the_json_brings_its_own_names
    message = Struct.new(:mention_names).new({ "1333" => "Citlali" })
    assert_equal({ "1333" => "Citlali" }, mentioned_names(message))
  end

  def test_a_message_without_mentions_has_no_names
    assert_equal({}, mentioned_names(Struct.new(:content).new("hi")))
    assert_equal({}, mentioned_names(FakeMessage.new("hi", [Struct.new(:id).new(5)]))) # no name known: skipped
  end

  def test_other_bots_are_marked_people_are_not
    assert_equal "Citlali [bot]", speaker_label(FakeUser.new(1333, "Citlali", bot: true))
    assert_equal "Pie", speaker_label(FakeUser.new(456, "Pie"))
    assert_equal "Bach", speaker_label(Struct.new(:id, :display_name).new(1, "Bach")) # no bot_account? at all
  end
end
