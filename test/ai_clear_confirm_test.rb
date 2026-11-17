require_relative "test_helper"
require_relative "fake_discord"
require_relative "../config"
require_relative "../ai_clear_confirm"
require_relative "clear_messages_test" # ClearChannel, ClearReadAsIs

# The confirm message the buttons are under: its id and when it was sent
ConfirmMessage = Struct.new(:id, :creation_time)

# A channel that also remembers the message Cake posts (post_clear_confirm)
class PostingChannel < ClearChannel
  attr_reader :sent

  def send_message(text, tts = false, embed = nil, attachments = nil, allowed_mentions = nil, reference = nil, components = nil)
    @sent = { text: text, components: components }
    nil
  end
end

# A button press. Remembers every answer Cake gave to Discord.
class ConfirmEvent
  attr_reader :custom_id, :user, :message, :channel, :responses, :updates, :edits, :deferred

  def initialize(custom_id, user, message, channel)
    @custom_id = custom_id
    @user = user
    @message = message
    @channel = channel
    @responses = []
    @updates = []
    @edits = []
    @deferred = false
  end

  # Cake as the event sees it: bot.profile.id
  def bot = FakeBot.new(FakeProfile.new(CAKE_ID))

  def respond(**options)
    @responses << options
    nil
  end

  def update_message(**options)
    @updates << options
    nil
  end

  def edit_response(**options)
    @edits << options
    nil
  end

  def defer_update
    @deferred = true
    nil
  end
end

CAKE_ID = 999
FakeProfile = Struct.new(:id)
FakeBot = Struct.new(:profile)

class AiClearConfirmTest < Minitest::Test
  PIE = HistoryAuthor.new(456, "Pie", false)
  CAKE = HistoryAuthor.new(CAKE_ID, "Cake", true)

  def setup
    LOGS.clear
    CLEAR_CONFIRM_HANDLED.clear
  end

  # history: message ids, oldest first, all sent a few minutes ago
  def confirm_event(custom_id, presser:, sent_at: Time.now, confirm_id: 1000, history: [], admin: true, authors: {}, replies: {})
    start = Time.now - 3600
    messages = history.map { |id| HistoryMessage.new(id, authors.fetch(id, PIE), "message #{id}", start + id, replies[id]) }
    channel = ClearChannel.new(messages)
    user = CommandUser.new(presser, "Presser", admin)
    ConfirmEvent.new(custom_id, user, ConfirmMessage.new(confirm_id, sent_at), channel)
  end

  def test_ids_round_trip
    yes, no = clear_confirm_ids(7, 20, "55", 900)
    assert_equal "aiclear:yes:7:20:55:900", yes
    assert_equal "aiclear:no:7", no
    assert_equal({ answer: :yes, requester_id: 7, amount: 20, user_id: "55", request_message_id: 900 }, parse_clear_confirm_id(yes))
    assert_equal :no, parse_clear_confirm_id(no)[:answer]
    assert_nil parse_clear_confirm_id("music:skip")
  end

  def test_everyone_target_is_zero_in_the_id
    assert_equal "aiclear:yes:7:5:0:900", clear_confirm_ids(7, 5, nil, 900).first
    assert_nil parse_clear_confirm_id("aiclear:yes:7:5:0:900")[:user_id]
  end

  def test_other_user_cannot_confirm
    event = confirm_event("aiclear:yes:7:2:0:900", presser: 8)
    clear_confirm_pressed(event, ClearReadAsIs)
    assert_equal({ content: "Only <@7> can confirm this.", ephemeral: true }, event.responses.last)
    assert_empty event.channel.deleted
  end

  def test_expired_confirm_deletes_nothing
    event = confirm_event("aiclear:yes:7:2:0:900", presser: 7, sent_at: Time.now - 61)
    clear_confirm_pressed(event, ClearReadAsIs)
    assert_includes event.updates.last[:content], "expired"
    assert_empty event.channel.deleted
  end

  def test_cancel_removes_buttons
    event = confirm_event("aiclear:no:7", presser: 7)
    clear_confirm_pressed(event, ClearReadAsIs)
    assert_equal({ content: "Cancelled.", components: [] }, event.updates.last)
  end

  def test_confirm_deletes_older_messages_and_the_conversation
    # history (oldest first): 1..5 old, 900 = request, 1000 = confirm message, 1050 = Cake's text reply (sent after the confirm)
    event = confirm_event("aiclear:yes:7:2:0:900", presser: 7, confirm_id: 1000, history: [1, 2, 3, 4, 5, 900, 1000, 1050],
                          authors: { 1050 => CAKE }, replies: { 1050 => 900 })
    clear_confirm_pressed(event, ClearReadAsIs)
    assert_equal [5, 4, 900, 1000, 1050].sort, event.channel.deleted.sort
    assert_equal({ content: "🧹 Deleting…", components: [] }, event.updates.first) # the buttons go at once
    assert_equal "🧹 Deleted 2 messages.", event.channel.temporary.last.first
  end

  def test_confirm_with_a_person_only_deletes_their_messages
    event = confirm_event("aiclear:yes:7:1:456:900", presser: 7, history: [1, 2, 900, 1000])
    clear_confirm_pressed(event, ClearReadAsIs)
    assert_equal [2, 900, 1000].sort, event.channel.deleted.sort
  end

  def test_second_press_does_not_delete_again
    history = [1, 2, 3, 4, 5, 6, 900, 1000]
    first = confirm_event("aiclear:yes:7:2:0:900", presser: 7, history: history)
    clear_confirm_pressed(first, ClearReadAsIs)
    second = ConfirmEvent.new(first.custom_id, first.user, first.message, first.channel)
    clear_confirm_pressed(second, ClearReadAsIs)
    assert_equal [6, 5, 900, 1000].sort, first.channel.deleted.sort
    assert_empty second.updates
  end

  def test_more_than_100_messages_are_deleted_in_chunks
    ids = (1..150).to_a + [900, 1000]
    event = confirm_event("aiclear:yes:7:100:0:900", presser: 7, history: ids)
    clear_confirm_pressed(event, ClearReadAsIs)
    assert_equal 102, event.channel.deleted.length
    assert_equal 2, event.channel.delete_calls
  end

  def test_the_requester_sees_an_error_after_the_buttons_are_gone
    event = confirm_event("aiclear:yes:7:2:0:900", presser: 7, history: [1, 2, 900, 1000])
    event.channel.instance_variable_set(:@delete_error, RuntimeError.new("boom"))
    clear_confirm_pressed(event, ClearReadAsIs)
    assert_equal({ content: clear_error_text(RuntimeError.new("boom")), components: [] }, event.edits.last)
  end

  def test_other_messages_after_the_request_stay
    # 920 = a user talking, 940 = a Cake message that is not a reply to the request, 1050 = Cake's reply
    event = confirm_event("aiclear:yes:7:2:0:900", presser: 7, history: [1, 2, 3, 900, 920, 940, 1000, 1050],
                          authors: { 940 => CAKE, 1050 => CAKE }, replies: { 1050 => 900 })
    clear_confirm_pressed(event, ClearReadAsIs)
    assert_equal [3, 2, 900, 1000, 1050].sort, event.channel.deleted.sort
  end

  def test_confirm_rechecks_admin
    event = confirm_event("aiclear:yes:7:2:0:900", presser: 7, admin: false)
    clear_confirm_pressed(event, ClearReadAsIs)
    assert event.responses.last[:ephemeral]
    assert_includes event.responses.last[:content], "Only admins"
    assert_empty event.channel.deleted
  end

  def test_unknown_button_is_ignored
    event = confirm_event("music:skip", presser: 7)
    assert_nil clear_confirm_pressed(event, ClearReadAsIs)
    assert_empty event.responses + event.updates
  end

  def test_a_discord_error_is_logged_not_raised
    event = confirm_event("aiclear:yes:7:2:0:900", presser: 7, history: [1, 2, 900, 1000])
    event.channel.instance_variable_set(:@delete_error, RuntimeError.new("boom"))
    assert_nil clear_confirm_pressed(event, ClearReadAsIs)
    assert(LOGS.any? { |line| line.include?("🧹") })
  end

  def test_post_sends_the_question_with_two_buttons
    channel = PostingChannel.new([])
    post_clear_confirm(channel, 7, 20, "55", 900)
    assert_equal "🧹 Delete the newest 20 messages from <@55> in this channel? Only <@7> can confirm.", channel.sent[:text]
    buttons = channel.sent[:components].to_a.flat_map { |row| row.to_h[:components] }
    assert_equal ["Delete", "Cancel"], buttons.map { |button| button[:label] }
    assert_equal ["aiclear:yes:7:20:55:900", "aiclear:no:7"], buttons.map { |button| button[:custom_id] }
  end

  def test_post_for_everyone_has_no_person_in_the_text
    channel = PostingChannel.new([])
    post_clear_confirm(channel, 7, 5, nil, 900)
    assert_equal "🧹 Delete the newest 5 messages in this channel? Only <@7> can confirm.", channel.sent[:text]
  end
end
