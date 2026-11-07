# Reads the prompt text files in prompts/. Everything the bot is told lives there, not in the code:
#   personality.default.txt  template for personality.txt (tracked by git)
#   personality.txt          this bot's own identity and tone (git ignored, created from the template)
#   capabilities.txt         commands and abilities, shared by every bot
#   chat_rules.txt           technical rules the code depends on
#   memory_rules.txt         when and how the bot saves, changes and removes memories
#   compaction.txt           instructions for summarizing old messages into memory
#   tidy_memory.txt          instructions for merging overlapping facts and spotting conflicts
#   open_question.txt        what to do when someone answers a question about their memory
PROMPTS_DIR = File.join(__dir__, 'prompts')

# read_prompt("chat_rules") => the text of prompts/chat_rules.txt
def read_prompt(name)
  File.read(File.join(PROMPTS_DIR, "#{name}.txt"), encoding: 'UTF-8').strip
end
