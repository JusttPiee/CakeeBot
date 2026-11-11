# The shared short-term memory of a server: what happened around Cake lately, in every channel.
#
# Each channel keeps its own chat history (chat_history.rb), so on its own Cake can't know that a minute
# ago, in another channel, someone asked it something or another bot tagged it. This log fills that gap.
# One line per exchange with Cake (question + Cake's answer), and one line when another bot tags Cake
# (Cake doesn't answer bots). When Cake answers in channel B, the lines from other channels go into
# the prompt as "Recently, in other channels".
#
# - RAM only: a restart starts with an empty log.
# - Short: at most RECENT_ACTIVITY_HOURS old, RECENT_ACTIVITY_MAX_PER_CHANNEL lines per channel
#   (so one busy channel can't push the others out), RECENT_ACTIVITY_MAX_LINES lines in total.
# - Private: a line from a channel not everyone can read is only ever used in that same channel
#   (see channel_visibility.rb). Whether a channel is public is decided when the line is written.
require_relative './config'
require_relative './notes_file' # one_line
require_relative './channel_visibility'

RECENT_ACTIVITY = {} # server id => [entry, ...], oldest first
RECENT_ACTIVITY_LOCK = Mutex.new

# What the log needs to know about a channel. Anything it can't find out counts as private.
def recent_channel_info(channel)
  { id: channel.id.to_s, name: channel.name.to_s, public: channel_public?(channel) }
end

# Someone asked Cake something and Cake answered
def record_recent_exchange(server_id, channel, speaker_id, speaker_name, question, answer, now = Time.now)
  entry = recent_entry(:exchange, channel, speaker_id, speaker_name, now)
  entry[:text] = shorten(question, RECENT_ACTIVITY_QUESTION_CHARS)
  entry[:answer] = shorten(answer, RECENT_ACTIVITY_ANSWER_CHARS)
  add_recent_entry(server_id, entry, now)
end

# Another bot tagged Cake, and Cake didn't answer (it never answers other bots)
def record_recent_tag(server_id, channel, speaker_id, speaker_name, text, now = Time.now)
  entry = recent_entry(:tagged, channel, speaker_id, speaker_name, now)
  entry[:text] = shorten(text, RECENT_ACTIVITY_QUESTION_CHARS)
  add_recent_entry(server_id, entry, now)
end

# The lines to show in channel_id: from OTHER channels (this channel's own lines are already in its history),
# public ones only, oldest first
def recent_entries_for(server_id, channel_id, now = Time.now)
  all_recent_entries(server_id, now).select { |entry| entry[:channel_id] != channel_id.to_s && entry[:public] }
end

# Every line still in the log, oldest first (the web UI shows them all, it is only for the admin)
def all_recent_entries(server_id, now = Time.now)
  RECENT_ACTIVITY_LOCK.synchronize do
    (RECENT_ACTIVITY[server_id.to_s] || []).select { |entry| fresh?(entry, now) }.map(&:dup)
  end
end

# !forgetme: their own lines, and lines that mention their id
def forget_recent_activity_of(server_id, user_id)
  id = user_id.to_s
  RECENT_ACTIVITY_LOCK.synchronize do
    RECENT_ACTIVITY[server_id.to_s]&.reject! do |entry|
      entry[:speaker_id] == id || "#{entry[:text]} #{entry[:answer]}".scan(/\d+/).include?(id)
    end
  end
end

# The lines as the AI reads them, one per line
def recent_activity_text(entries)
  entries.map { |entry| recent_line(entry) }.join("\n")
end

# --- helpers ---

def recent_entry(kind, channel, speaker_id, speaker_name, now)
  { kind: kind, time: now, channel_id: channel[:id].to_s, channel_name: channel[:name].to_s, public: channel[:public] == true,
    speaker_id: speaker_id.to_s, speaker_name: speaker_name.to_s, text: "", answer: nil }
end

def add_recent_entry(server_id, entry, now)
  RECENT_ACTIVITY_LOCK.synchronize do
    entries = (RECENT_ACTIVITY[server_id.to_s] ||= [])
    entries << entry
    RECENT_ACTIVITY[server_id.to_s] = trimmed_recent_entries(entries, now)
  end
end

# Too old out first, then the oldest lines of a too-busy channel, then the oldest lines overall
def trimmed_recent_entries(entries, now)
  kept = entries.select { |entry| fresh?(entry, now) }
  kept = kept.group_by { |entry| entry[:channel_id] }.values.flat_map { |lines| lines.last(RECENT_ACTIVITY_MAX_PER_CHANNEL) }
  kept.sort_by { |entry| entry[:time] }.last(RECENT_ACTIVITY_MAX_LINES)
end

def fresh?(entry, now)
  now - entry[:time] <= RECENT_ACTIVITY_HOURS * 3600
end

# One line of text, at most max characters (plus "…" when it was cut)
def shorten(text, max)
  flat = one_line(text)
  flat.length > max ? "#{flat[0, max]}…" : flat
end

# "[12:21 #test-2] Piee (694...) → you: "..." — you: "...""
def recent_line(entry)
  start = "[#{entry[:time].strftime('%H:%M')} ##{entry[:channel_name]}] #{entry[:speaker_name]} (#{entry[:speaker_id]})"
  return "#{start} tagged you: \"#{entry[:text]}\" (you did not answer)" if entry[:kind] == :tagged

  "#{start} → you: \"#{entry[:text]}\" — you: \"#{entry[:answer]}\""
end
