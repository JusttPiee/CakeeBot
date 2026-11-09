require_relative "test_helper"
require_relative "../config"
require_relative "../silent_chat"

# Pretend Discord pieces for !silent (only what silent_chat.rb uses)
module SilentFakes
  Author = Struct.new(:id, :display_name)
  Profile = Struct.new(:id)
  BotMember = Struct.new(:display_name)
  Bot = Struct.new(:profile)
  Server = Struct.new(:id, :bot)

  # A message in the channel's history, like a discordrb Message
  OldMessage = Struct.new(:author, :content, :creation_time, :id) do
    def attachments = []
    def reply? = false
  end

  # The !silent message. delete can fail, like without "Manage Messages".
  class Message
    attr_reader :content, :id, :deleted

    def initialize(content, id, delete_error: nil)
      @content = content
      @id = id
      @delete_error = delete_error
      @deleted = false
    end

    def delete
      raise @delete_error if @delete_error

      @deleted = true
    end
  end

  # The asker: pm(text) sends a DM, pm with no text gives the DM channel (for typing)
  class Asker < Author
    attr_accessor :dms, :dm_error

    def pm(text = nil)
      return Struct.new(:start_typing).new(nil) if text.nil?
      raise dm_error if dm_error

      (self.dms ||= []) << text
    end
  end

  class Channel
    attr_reader :id, :name, :temporary

    def initialize(messages)
      @messages = messages # oldest first
      @id = 555
      @name = "general"
      @temporary = []
    end

    # Like discordrb's channel.send_temporary_message: kept with how long it stays
    def send_temporary_message(text, seconds)
      @temporary << [text, seconds]
      nil
    end

    def history(amount) = @messages.last(amount).reverse
    def cached_nickname(_user_id) = nil
  end

  # Reads the fake channel as it is (no Discord)
  module ReadAsIs
    def self.new(channel, _bot) = channel
  end

  # No send_temporary_message on purpose: discordrb 3.8's version is broken (see temporary_note.rb)
  class Event
    attr_reader :message, :author, :channel, :server, :responses

    def initialize(content, channel: Channel.new([]), server: Server.new(1, BotMember.new("Cake")), delete_error: nil)
      @message = Message.new(content, 900, delete_error: delete_error)
      @author = Asker.new(123, "Bach")
      @channel = channel
      @server = server
      @responses = []
    end

    def temporary = @channel.temporary

    def bot = Bot.new(Profile.new(999))

    def respond(text)
      @responses << text
      nil
    end

  end
end

class SilentChatTest < Minitest::Test
  include SilentFakes

  def setup
    clear_test_memory
    LOGS.clear
  end

  def run_silent(event, client = FakeClient.new(answers: ["Psst, here you go"]))
    silent_command(event, client, ReadAsIs)
    client
  end

  def test_the_question_without_the_command
    assert_equal "what is my rank?", silent_question("!silent what is my rank?")
    assert_equal "line one\nline two", silent_question("!SILENT line one\nline two")
    assert_equal "", silent_question("!silent")
  end

  def test_deletes_the_question_and_answers_in_dms
    event = Event.new("!silent what is my rank?")
    run_silent(event)
    assert event.message.deleted
    assert_equal ["Psst, here you go"], event.author.dms
    assert_empty event.responses # nothing in the channel
    assert_empty event.temporary
  end

  def test_the_ai_gets_the_question_and_the_channel_context
    old = OldMessage.new(Author.new(456, "Pie"), "valorant tonight?", Time.now - 60, 1)
    event = Event.new("!silent should I join Pie?", channel: Channel.new([old]))
    client = run_silent(event)
    input = client.requests.first[:input]
    assert_includes input.first[:content], "Pie (456): valorant tonight?"
    assert_includes input.last[:content], "Bach (123): should I join Pie?"
    assert_includes input.last[:content], "privately"
  end

  def test_the_question_is_not_there_twice_when_it_could_not_be_deleted
    still_there = OldMessage.new(Author.new(123, "Bach"), "!silent hi", Time.now, 900)
    event = Event.new("!silent hi", channel: Channel.new([still_there]), delete_error: RuntimeError.new("no permission"))
    client = run_silent(event)
    assert_equal 1, client.requests.first[:input].length
    assert_equal ["Psst, here you go"], event.author.dms # still answered privately
    assert(LOGS.any? { |line| line.include?("could not delete") })
  end

  def test_long_answers_are_split_into_several_dms
    event = Event.new("!silent tell me a story")
    run_silent(event, FakeClient.new(answers: ["word " * 1000]))
    assert_operator event.author.dms.length, :>, 1
  end

  def test_says_so_in_the_channel_when_dms_are_closed
    event = Event.new("!silent hi")
    event.author.dm_error = RuntimeError.new("Cannot send messages to this user")
    run_silent(event)
    text, seconds = event.temporary.last
    assert_includes text, "couldn't DM you"
    assert_equal SILENT_NOTICE_SECONDS, seconds
  end

  def test_an_empty_question_shows_the_usage_for_a_moment
    event = Event.new("!silent")
    client = run_silent(event)
    assert_empty client.requests
    assert_equal SILENT_USAGE, event.temporary.last.first
    assert event.message.deleted
  end

  def test_when_the_ai_fails_the_dm_says_so
    event = Event.new("!silent hi")
    run_silent(event, FakeClient.new(answers: [""]))
    assert_includes event.author.dms.last, "unavailable"
  end

  def test_only_in_a_server
    event = Event.new("!silent hi", server: nil)
    run_silent(event)
    assert_includes event.responses.last, "only works in a server"
  end

  def test_memory_tools_save_for_the_asker
    tool_call = { "type" => "function_call", "name" => "remember_about_me", "call_id" => "c1",
                  "arguments" => '{"fact":"likes pho"}' }
    event = Event.new("!silent remember I like pho")
    run_silent(event, FakeClient.new(answers: [{ tool_calls: [tool_call] }, "Saved!"]))
    assert read_user_note(1, 123)
    assert_equal ["Saved!"], event.author.dms
  end

  def test_the_ai_knows_about_the_command
    assert_includes CAPABILITIES, "!silent"
  end
end
