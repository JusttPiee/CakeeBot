# Short notes like "[music: Skipped.]" added to the AI's reply, so the chat history shows
# which commands Cake ran for the person. The command tools add them to context[:command_labels].
require_relative './config'

SILENT_COMMAND_TEXT = "Not available in a private question."

# Adds "[text]" to the label list, cut to COMMAND_LABEL_MAX_CHARS (a cut label ends with "…]").
# Does nothing when the context has no label list.
def add_command_label(context, text)
  labels = context[:command_labels]
  return unless labels.is_a?(Array)

  labels << command_label(text)
end

def command_label(text)
  label = "[#{text.to_s.gsub(/\s+/, ' ').strip}]"
  return label if label.length <= COMMAND_LABEL_MAX_CHARS

  label[0, COMMAND_LABEL_MAX_CHARS - 2] + "…]"
end
