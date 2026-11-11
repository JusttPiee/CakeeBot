# Can everyone in the server read this channel?
#
# Used by the shared recent memory (recent_activity.rb): a line from channel A may only be shown in
# another channel B if everyone who can see B can also see A. Without the full member list (a privileged
# Discord intent) that can only be proven one way for sure: A is readable by everyone. So:
#   public channel  -> its lines may be shown anywhere in the server
#   anything else   -> its lines stay in that channel
#
# When in doubt, the answer is "not public": a private line wrongly kept in its channel costs nothing,
# a private line shown in a public channel can't be taken back.

# true only if @everyone can read the channel and nobody is denied it
def channel_public?(channel)
  return false if channel.nil? || channel.thread? # private threads look like threads too; never share them

  overwrites = channel.permission_overwrites.values
  return false if overwrites.any? { |overwrite| overwrite.deny.read_messages }

  everyone_can_read?(channel.server.everyone_role, overwrites)
rescue StandardError
  false
end

# Either the channel allows @everyone explicitly, or the server lets @everyone read channels by default
def everyone_can_read?(everyone, overwrites)
  everyone_overwrite = overwrites.find { |overwrite| overwrite.id == everyone.id }
  return true if everyone_overwrite&.allow&.read_messages

  everyone.permissions.read_messages ? true : false
end
