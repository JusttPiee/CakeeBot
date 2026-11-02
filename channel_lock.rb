# discordrb handles every message in its own thread. If two people send a message at the same time,
# two threads would change the same chat history at once and mix up the order.
# A lock per channel makes messages in one channel wait their turn. Other channels are not affected.

CHANNEL_LOCKS = {}
CHANNEL_LOCKS_GUARD = Mutex.new # protects CHANNEL_LOCKS itself while a new lock is being created

def with_channel_lock(channel_id)
  lock = CHANNEL_LOCKS_GUARD.synchronize { CHANNEL_LOCKS[channel_id] ||= Mutex.new }
  lock.synchronize { yield }
end
