require_relative "test_helper"
require_relative "../config"
require_relative "../help_command"

# A pretend channel that remembers the help message it was sent
class HelpChannel
  attr_reader :sent

  def send_message(content, tts, embed, attachments, allowed_mentions, reference, components)
    @sent = { content: content, embed: embed, components: components }
    nil
  end
end

HelpProfile = Struct.new(:avatar_url)
HelpBot = Struct.new(:profile)
HelpUser = Struct.new(:id)

# A pretend !help command event
class HelpEvent
  attr_reader :channel, :user, :bot

  def initialize(user_id:)
    @channel = HelpChannel.new
    @user = HelpUser.new(user_id)
    @bot = HelpBot.new(HelpProfile.new("https://cdn/avatar.png"))
  end

  def sent_embed = @channel.sent[:embed]
end

# A pretend menu selection: remembers update_message and respond
class HelpSelectEvent
  attr_reader :custom_id, :user, :values, :bot, :updated, :responded

  def initialize(custom_id:, user_id:, values:)
    @custom_id = custom_id
    @user = HelpUser.new(user_id)
    @values = values
    @bot = HelpBot.new(HelpProfile.new(nil))
  end

  def update_message(**fields)
    @updated = fields
  end

  def respond(**fields)
    @responded = fields
  end
end

class HelpCommandTest < Minitest::Test
  def test_plain_help_shows_overview_with_menu
    event = HelpEvent.new(user_id: 7)
    assert_nil help_command(event, [])
    assert_equal 5, event.sent_embed.fields.length
    assert_equal "help:7", event.channel.sent[:components].to_a.first[:components].first[:custom_id]
  end

  def test_help_music_opens_music
    event = HelpEvent.new(user_id: 7)
    help_command(event, ["music"])
    assert_includes event.sent_embed.title, "Music"
  end

  def test_unknown_word_shows_overview
    event = HelpEvent.new(user_id: 7)
    help_command(event, ["pizza"])
    assert_equal 5, event.sent_embed.fields.length
  end

  def test_owner_switches_page
    event = HelpSelectEvent.new(custom_id: "help:7", user_id: 7, values: ["games"])
    help_menu_selected(event)
    assert_includes event.updated[:embeds].first.title, "Games"
    menu = event.updated[:components].to_a.first[:components].first
    assert menu[:options].find { |option| option[:value] == "games" }[:default]
  end

  def test_owner_goes_back_to_overview
    event = HelpSelectEvent.new(custom_id: "help:7", user_id: 7, values: ["overview"])
    help_menu_selected(event)
    assert_equal 5, event.updated[:embeds].first.fields.length
  end

  def test_other_user_gets_private_reply
    event = HelpSelectEvent.new(custom_id: "help:7", user_id: 8, values: ["games"])
    help_menu_selected(event)
    assert_nil event.updated
    assert_equal({ content: "Type `!help` to get your own.", ephemeral: true }, event.responded)
  end

  def test_custom_id_round_trip
    assert_equal 42, help_menu_owner("help:42")
    assert_nil help_menu_owner("music:skip")
    assert_nil help_menu_owner("help:abc")
  end

  def test_help_message_is_deleted_later
    channel = Object.new
    message = Object.new
    def message.delete = (@deleted = true)
    def message.deleted? = @deleted
    channel.define_singleton_method(:send_message) { |*_args| message }
    waits = []
    later = []
    scheduler = ->(seconds, &block) { waits << seconds; later << block }

    post_help_page(channel, 7, nil, nil, scheduler: scheduler)
    assert_equal [HELP_CLOSE_AFTER_MINUTES * 60], waits
    refute message.deleted?

    later.each(&:call)
    assert message.deleted?
  end

  def test_already_deleted_help_message_is_only_logged
    message = Object.new
    def message.delete = raise("Unknown Message")
    delete_help_message(message)
    assert(LOGS.any? { |line| line.include?("could not delete a help message") })
  end

  def test_a_crash_is_logged_not_raised
    event = HelpEvent.new(user_id: 7)
    def event.channel = raise("Discord is down")
    assert_nil help_command(event, [])
    assert(LOGS.any? { |line| line.include?("📘 !help failed") })
  end
end
