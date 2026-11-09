# OpenAI's Moderation API: checks if a text is harmful (hate, harassment, sexual, violence, self-harm...).
# It is free. Cake uses it before saving anything to long-term memory, so nobody can make
# the bot store insults or worse in its notes and repeat them later.
#
# If the check itself fails (OpenAI down, no client in tests), the text is allowed:
# memory saving should not break just because the safety check is unavailable. The failure is logged.
require_relative './config'

# The AI's answer when a memory was refused. It does not say which category, so it can't be used to probe the filter.
MODERATION_REFUSED = "Error: this was not saved because it looks harmful (insults, hate, sexual or violent content). " \
                     "Tell the sender you won't keep that in memory."

# An error message for the AI if the text is harmful, or nil if it may be saved
def check_moderation(text, context)
  flags = moderation_flags(context[:client], text)
  return nil if flags.nil? || flags.empty?

  log "🛡️ Memory refused by moderation for #{context[:requester_name]} (#{context[:requester_id]}): #{flags.join(', ')}"
  MODERATION_REFUSED
end

# The names of the categories the text was flagged for ([] = clean), or nil if the check could not run
def moderation_flags(client, text)
  return nil if client.nil? || text.to_s.strip.empty?

  response = client.moderations(parameters: { model: MODERATION_MODEL, input: text.to_s })
  result = response.dig("results", 0)
  return nil if result.nil?
  return [] unless result["flagged"]

  result["categories"].to_h.select { |_category, flagged| flagged }.keys
rescue StandardError => e
  log "⚠️ Moderation check failed (#{e.class}), saving without it"
  nil
end
