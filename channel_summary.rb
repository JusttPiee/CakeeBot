# The rolling summary of one AI channel: memory/<server_id>/channels/<channel_id>.md
# Compaction rewrites it every time old messages are dropped from the history, so Cake keeps
# the thread of older conversations. Only this channel's replies see it.
#
#   last_message_id: 1300000000000000000
#   updated: 2026-11-04 14:02
#
#   Bach and Piee planned a Valorant night...
#
# last_message_id = the newest Discord message already in the summary. After a restart,
# only messages newer than that are loaded, so nothing is in both the summary and the history.
require_relative './memory_store'
require_relative './notes_file'

def channel_summary_path(channel_id)
  "channels/#{channel_id}.md"
end

# { text:, last_message_id: } (text "" and id nil when there is no summary yet)
def read_channel_summary(server_id, channel_id)
  text = read_memory_file(server_id, channel_summary_path(channel_id))
  return { text: "", last_message_id: nil } if text.nil?

  note = parse_note(text)
  id = note[:headers]["last_message_id"].to_s
  { text: note[:body], last_message_id: id.match?(/\A\d+\z/) ? id.to_i : nil }
end

def write_channel_summary(server_id, channel_id, text, last_message_id, now = Time.now)
  headers = { "last_message_id" => last_message_id.to_s, "updated" => now.strftime("%Y-%m-%d %H:%M") }
  write_memory_file(server_id, channel_summary_path(channel_id), format_note(headers, text))
end
