# A short message in the channel that deletes itself after a few seconds (!clear reports, !silent notices).
#
# Why not event.send_temporary_message: in discordrb 3.8 it passes its arguments on to the channel in the
# wrong order (it skips message_reference, so flags = 0 lands where components should be), and the
# message thread crashes with "undefined method `to_a' for an instance of Integer".
# channel.send_temporary_message has the right order, so it is called directly.
def send_temporary_note(channel, text, seconds)
  channel.send_temporary_message(text, seconds)
end
