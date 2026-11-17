require_relative "test_helper"
require "minitest/mock"
require_relative "../message_edit"

class MessageEditTest < Minitest::Test
  # A real discordrb Message with only what an edit needs: the bot's token, the channel and the id
  def sent_message
    message = Discordrb::Message.allocate
    message.instance_variable_set(:@bot, Struct.new(:token).new("Bot test-token"))
    message.instance_variable_set(:@channel, Struct.new(:id).new(555))
    message.instance_variable_set(:@id, 77)
    message
  end

  # Discord pings the person replied to again when an edit has no allowed_mentions
  def test_edit_tells_discord_to_ping_nobody
    calls = []
    fake_api = lambda do |*args|
      calls << args
      "{}"
    end
    message = sent_message
    result = Discordrb::API::Channel.stub(:edit_message, fake_api) { message.edit_without_ping("Hi!") }

    assert_equal [["Bot test-token", 555, 77, "Hi!", { replied_user: false }]], calls
    assert_same message, result
  end

  def test_a_refused_edit_raises
    message = sent_message
    assert_raises(RuntimeError) do
      Discordrb::API::Channel.stub(:edit_message, ->(*) { raise "Unknown Message" }) { message.edit_without_ping("Hi!") }
    end
  end
end
