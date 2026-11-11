require_relative "test_helper"
require_relative "../channel_visibility"

# Can everyone in the server read this channel? Only then may a line from it be shown in other channels.
class ChannelVisibilityTest < Minitest::Test
  Perms = Struct.new(:read_messages)
  Role = Struct.new(:id, :permissions)
  Server = Struct.new(:everyone_role)
  Overwrite = Struct.new(:id, :type, :allow, :deny)

  EVERYONE_ID = 1

  class Channel
    attr_reader :server

    def initialize(server, overwrites, thread: false, broken: false)
      @server = server
      @overwrites = overwrites
      @thread = thread
      @broken = broken
    end

    def thread? = @thread

    def permission_overwrites
      raise "Discord data missing" if @broken

      @overwrites.to_h { |overwrite| [overwrite.id, overwrite] }
    end
  end

  def server(everyone_can_read: true)
    Server.new(Role.new(EVERYONE_ID, Perms.new(everyone_can_read)))
  end

  def overwrite(id, type, allow: false, deny: false)
    Overwrite.new(id, type, Perms.new(allow), Perms.new(deny))
  end

  def test_a_channel_everyone_can_read_is_public
    assert channel_public?(Channel.new(server, []))
    assert channel_public?(Channel.new(server, [overwrite(55, :role, allow: true)])) # an allow changes nothing
  end

  def test_everyone_denied_is_private
    refute channel_public?(Channel.new(server, [overwrite(EVERYONE_ID, :role, deny: true)]))
  end

  def test_a_role_or_member_deny_makes_it_private
    refute channel_public?(Channel.new(server, [overwrite(55, :role, deny: true)]))
    refute channel_public?(Channel.new(server, [overwrite(777, :member, deny: true)]))
  end

  def test_everyone_without_base_permission_but_allowed_on_the_channel_is_public
    channel = Channel.new(server(everyone_can_read: false), [overwrite(EVERYONE_ID, :role, allow: true)])
    assert channel_public?(channel)
  end

  def test_everyone_without_permission_is_private
    refute channel_public?(Channel.new(server(everyone_can_read: false), []))
    refute channel_public?(Channel.new(server(everyone_can_read: false), [overwrite(55, :role, allow: true)]))
  end

  def test_threads_are_never_public
    refute channel_public?(Channel.new(server, [], thread: true))
  end

  def test_an_error_counts_as_private
    refute channel_public?(Channel.new(server, [], broken: true))
    refute channel_public?(Struct.new(:id).new(5)) # not even a real channel
    refute channel_public?(nil)
  end
end
