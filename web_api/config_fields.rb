# Which settings the web UI may change, and which values are allowed.
# Only the names listed here can ever be written to settings.json: this list is the gate.
# The defaults and the explanations stay in config.rb. The names shown on the page are in the
# React app's dictionaries (web/src/i18n), under "config.<NAME>.label".
require_relative '../config'

REASONING_LEVELS = %w[none low medium high xhigh].freeze

def integer_field(name, min, max)
  { name: name, type: "integer", min: min, max: max, options: nil }
end

def choice_field(name, options)
  { name: name, type: "choice", min: nil, max: nil, options: options }
end

# The groups are shown on the Config page in this order
CONFIG_GROUPS = [
  { id: "chat", fields: [
    choice_field("OPENAI_REASONING_EFFORT", REASONING_LEVELS),
    choice_field("OPENAI_FALLBACK_REASONING_EFFORT", REASONING_LEVELS),
    integer_field("OPENAI_MAX_OUTPUT_TOKENS", 500, 32_000),
    integer_field("MAX_TOOL_ROUNDS", 1, 20)
  ] },
  { id: "history", fields: [
    integer_field("MAX_HISTORY_MESSAGES", 10, 200),
    integer_field("MAX_HISTORY_TOKENS", 1000, 50_000),
    integer_field("COMPACT_TARGET_MESSAGES", 4, 150),
    integer_field("COMPACT_TARGET_TOKENS", 500, 40_000),
    integer_field("HARD_MAX_HISTORY_MESSAGES", 15, 400),
    integer_field("HARD_MAX_HISTORY_TOKENS", 1500, 100_000),
    choice_field("COMPACTION_REASONING_EFFORT", REASONING_LEVELS)
  ] },
  { id: "tools", fields: [
    integer_field("SEARCH_MAX_RESULTS", 1, 10),
    integer_field("WEBPAGE_MAX_CHARS", 1000, 50_000),
    integer_field("IMAGE_MAX_PER_REPLY", 1, 10),
    integer_field("TEXT_FILE_MAX_PER_REPLY", 1, 10)
  ] },
  { id: "search", fields: [
    integer_field("MEMORY_SEARCH_RESULTS", 1, 20),
    integer_field("CHANNEL_SEARCH_MAX_MESSAGES", 100, 5000),
    integer_field("CHANNEL_SEARCH_RESULTS", 1, 30),
    integer_field("CHANNEL_SEARCHES_PER_REPLY", 1, 10)
  ] },
  { id: "buildmemory", fields: [
    integer_field("BUILD_MEMORY_MESSAGES_PER_CHANNEL", 100, 10_000),
    integer_field("BUILD_MEMORY_MIN_MESSAGES", 1, 100),
    integer_field("BUILD_MEMORY_MAX_PEOPLE", 1, 200),
    integer_field("BUILD_MEMORY_MAX_CHARS_PER_PERSON", 1000, 50_000),
    choice_field("BUILD_MEMORY_REASONING_EFFORT", REASONING_LEVELS)
  ] },
  { id: "clear", fields: [
    integer_field("CLEAR_MAX_MESSAGES", 1, 100), # Discord deletes at most 100 messages in one go
    integer_field("CLEAR_SCAN_MESSAGES", 100, 2000),
    integer_field("CLEAR_REPORT_SECONDS", 1, 60)
  ] }
].freeze

# The history is compacted from the high mark down to the low mark, and the hard maximum is the safety net
# above both (see config.rb). They only make sense in this order: [low, high, hard maximum].
CONFIG_ORDER_RULES = [
  %w[COMPACT_TARGET_MESSAGES MAX_HISTORY_MESSAGES HARD_MAX_HISTORY_MESSAGES],
  %w[COMPACT_TARGET_TOKENS MAX_HISTORY_TOKENS HARD_MAX_HISTORY_TOKENS]
].freeze

def config_fields
  CONFIG_GROUPS.flat_map { |group| group[:fields] }
end

def config_field_names
  config_fields.map { |field| field[:name] }
end

# What is wrong with one value, or nil if it is fine
def config_value_error(field, value)
  if field[:type] == "choice"
    return field[:options].include?(value) ? nil : "Must be one of: #{field[:options].join(', ')}."
  end
  return "Must be a whole number." unless value.is_a?(Integer)

  value.between?(field[:min], field[:max]) ? nil : "Must be from #{field[:min]} to #{field[:max]}."
end

# { "NAME" => "what is wrong" } for a full set of values (every field has one). Empty when all is fine.
def config_errors(values)
  errors = {}
  config_fields.each do |field|
    error = config_value_error(field, values[field[:name]])
    errors[field[:name]] = error if error
  end
  errors.merge(config_order_errors(values, errors))
end

# The order rules, checked only where the three values themselves are fine.
# The message goes on the middle setting, the one that must sit between the other two.
def config_order_errors(values, errors)
  order_errors = {}
  CONFIG_ORDER_RULES.each do |low, middle, high|
    next if errors.key?(low) || errors.key?(middle) || errors.key?(high)
    next if values[low] < values[middle] && values[middle] < values[high]

    order_errors[middle] = "Must be above #{low} (#{values[low]}) and below #{high} (#{values[high]})."
  end
  order_errors
end
