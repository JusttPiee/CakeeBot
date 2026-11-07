# What the bot remembers about the questions it asks when memories conflict (see memory_tidy.rb).
# Saved per person in tidy_state.md:
#   open_question:   the question still waiting for an answer. The AI is told about it when that person
#                    talks, so a one-word answer like "Bloo" still ends up in memory.
#   asked_questions: the newest questions asked, so tidying doesn't ask about the same thing again.
#   question, question_fingerprint: a question waiting to be sent, and the memories it was about.
#
# An open question closes when the memories it was about change, or after OPEN_QUESTION_MAX_MESSAGES
# messages from that person, so an ignored question doesn't stay in the prompt forever.
require_relative './config'
require_relative './prompts'
require_relative './tidy_state'

OPEN_QUESTION_INSTRUCTIONS = read_prompt("open_question") # loaded once, at startup

# Call this after the question was really sent, without holding the memory lock
def record_asked_question(server_id, user_id, question)
  update_tidy_state(server_id, user_id,
                    open_question: { text: question, fingerprint: current_memories_fingerprint(server_id, user_id), messages_left: OPEN_QUESTION_MAX_MESSAGES },
                    asked_questions: (asked_questions_of(server_id, user_id) + [question]).last(ASKED_QUESTIONS_KEPT))
end

def asked_questions_of(server_id, user_id)
  tidy_state_of(server_id, user_id)["asked_questions"].to_a
end

# The text of the open question, or nil
def open_question_text(server_id, user_id)
  open_question = tidy_state_of(server_id, user_id)["open_question"]
  open_question && open_question["text"]
end

# Called once for each message this person sent, after the reply
def age_open_question(server_id, user_id)
  open_question = tidy_state_of(server_id, user_id)["open_question"]
  return if open_question.nil?

  messages_left = open_question["messages_left"].to_i - 1
  if messages_left <= 0 || open_question["fingerprint"] != current_memories_fingerprint(server_id, user_id)
    update_tidy_state(server_id, user_id, open_question: nil)
  else
    update_tidy_state(server_id, user_id, open_question: open_question.merge("messages_left" => messages_left))
  end
end

# The part of the system prompt about the open question ("" if there is none)
def open_question_prompt(server_id, user_id)
  question = open_question_text(server_id, user_id)
  question ? OPEN_QUESTION_INSTRUCTIONS.gsub("{question}") { question } : ""
end

# A question that couldn't be sent yet. Without the memories it was about, it could go out of date.
def save_pending_question(server_id, user_id, question)
  update_tidy_state(server_id, user_id, question: question, question_fingerprint: current_memories_fingerprint(server_id, user_id))
end

# The waiting question, or nil. It is removed, so it is only asked once.
# Dropped if the memories changed since, because the answer may already be saved.
def take_pending_question(server_id, user_id)
  state = tidy_state_of(server_id, user_id)
  question = state["question"]
  return nil if question.nil?

  update_tidy_state(server_id, user_id, question: nil, question_fingerprint: nil)
  state["question_fingerprint"] == current_memories_fingerprint(server_id, user_id) ? question : nil
end

# --- helpers ---

def current_memories_fingerprint(server_id, user_id)
  memories = with_server_memory_lock(server_id) { memories_to_check(server_id, user_id) }
  facts_fingerprint(memories[:own] + memories[:related])
end
