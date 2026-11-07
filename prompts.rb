# Reads the prompt text files in prompts/. Everything the bot is told lives there, not in the code:
#   personality.default.txt  template for personality.txt (tracked by git)
#   personality.txt          this bot's own identity and tone (git ignored, created from the template)
#   capabilities.txt         commands and abilities, shared by every bot
#   chat_rules.txt           technical rules the code depends on
#   compaction.txt           instructions for summarizing old messages into memory
PROMPTS_DIR = File.join(__dir__, 'prompts')

# read_prompt("chat_rules") => the text of prompts/chat_rules.txt
def read_prompt(name)
  File.read(File.join(PROMPTS_DIR, "#{name}.txt"), encoding: 'UTF-8').strip
end
