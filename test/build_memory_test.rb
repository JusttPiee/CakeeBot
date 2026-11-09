require_relative "test_helper"
require_relative "fake_discord"
require "json"
require_relative "../config"
require_relative "../tool_list"
require_relative "../build_memory"
require_relative "../forget_me"

# FakeClient (answers) plus OpenAI's Moderation API: a text with a word from bad_words is flagged
class BuildMemoryClient < FakeClient
  def initialize(answers:, bad_words: [])
    super(answers: answers)
    @bad_words = bad_words
  end

  def moderations(parameters:)
    flagged = @bad_words.any? { |word| parameters[:input].include?(word) }
    { "results" => [{ "flagged" => flagged, "categories" => { "harassment" => flagged } }] }
  end
end

# !buildmemory: personality notes from old messages in every channel
class BuildMemoryTest < Minitest::Test
  BACH = HistoryAuthor.new(123, "Bach", false)
  PIE = HistoryAuthor.new(456, "Pie", false)
  CAKE = HistoryAuthor.new(999, "Cake", true)
  ADMIN = CommandUser.new(123, "Bach", true)

  def setup
    clear_test_memory
    LOGS.clear
    BUILD_MEMORY_RUNNING.clear
  end

  def note_json(personality, description = "gamer")
    { personality: personality, description: description }.to_json
  end

  def server_with(*channels)
    HistoryServer.new(1, "Test Server", channels, CAKE)
  end

  # --- grouping and choosing ---

  def test_groups_messages_by_person_without_bots
    messages = plain_test_messages(history_messages(3, BACH) + history_messages(2, CAKE))
    people = messages_by_person(messages)
    assert_equal ["123"], people.keys
    assert_equal 3, people["123"][:messages].length
  end

  def test_uses_the_newest_name
    old = HistoryMessage.new(1, HistoryAuthor.new(123, "OldName", false), "hi", Time.new(2026, 1, 1))
    new = HistoryMessage.new(2, BACH, "hi", Time.new(2026, 2, 1))
    assert_equal "Bach", messages_by_person(plain_test_messages([new, old]))["123"][:name]
  end

  def test_skips_people_with_too_few_messages
    people = messages_by_person(plain_test_messages(history_messages(BUILD_MEMORY_MIN_MESSAGES - 1, PIE)))
    plan = plan_memory_build(1, people)
    assert_empty plan[:chosen]
    assert_equal 1, plan[:too_few]
  end

  def test_skips_people_who_turned_personality_notes_off
    forget_user(1, 456)
    people = messages_by_person(plain_test_messages(history_messages(10, PIE)))
    plan = plan_memory_build(1, people)
    assert_empty plan[:chosen]
    assert_equal 1, plan[:turned_off]
  end

  def test_most_active_people_first
    messages = plain_test_messages(history_messages(6, PIE) + history_messages(9, BACH).map { |m| HistoryMessage.new(m.id + 100, m.author, m.content, m.creation_time) })
    plan = plan_memory_build(1, messages_by_person(messages))
    assert_equal %w[123 456], plan[:chosen].map(&:first)
  end

  def test_only_the_newest_messages_that_fit
    person = messages_by_person(plain_test_messages(history_messages(1000, BACH, text: "x" * 100)))["123"]
    lines = person_message_lines(person)
    assert lines.length <= BUILD_MEMORY_MAX_CHARS_PER_PERSON
    assert lines.end_with?("#{'x' * 100} 1000") # the newest is kept, and comes last
    refute_includes lines, "#{'x' * 100} 1\n" # the oldest is not
  end

  # --- the whole build ---

  def test_builds_a_note_for_each_person
    channel = HistoryChannel.new(history_messages(6, BACH, text: "valorant"))
    client = BuildMemoryClient.new(answers: [note_json("Plays Valorant every day")])
    report = build_server_memory(client, 1, [channel], "Cake")
    assert_equal 1, report[:results][:built]
    assert_equal "Plays Valorant every day", read_user_note(1, 123)[:personality]
    assert_includes read_memory_file(1, "MEMORY.md"), "Bach (123): gamer"
  end

  def test_sends_only_that_persons_messages
    channel = HistoryChannel.new(history_messages(6, BACH, text: "from bach") +
                                 history_messages(6, PIE, text: "from pie").map { |m| HistoryMessage.new(m.id + 100, m.author, m.content, m.creation_time) })
    client = BuildMemoryClient.new(answers: [note_json("x")])
    build_server_memory(client, 1, [channel], "Cake")
    inputs = client.requests.map { |request| request[:input].first[:content] }
    bach_input = inputs.find { |input| input.include?("Bach (123)") }
    refute_includes bach_input, "from pie"
  end

  def test_keeps_saved_facts
    append_remembered_fact(1, 123, "Bach", "call me Boss")
    channel = HistoryChannel.new(history_messages(6, BACH))
    build_server_memory(BuildMemoryClient.new(answers: [note_json("Chill")]), 1, [channel], "Cake")
    assert_includes read_user_note(1, 123)[:remembered].first, "call me Boss"
  end

  def test_sends_the_current_note_so_it_is_updated
    change_user_personality(1, 123, "Bach", "Loves cats", "cat person")
    client = BuildMemoryClient.new(answers: [note_json("Loves cats and Valorant")])
    build_server_memory(client, 1, [HistoryChannel.new(history_messages(6, BACH))], "Cake")
    assert_includes client.requests.first[:input].first[:content], "Loves cats"
  end

  def test_an_empty_answer_writes_nothing
    report = build_server_memory(BuildMemoryClient.new(answers: [note_json("", "")]), 1, [HistoryChannel.new(history_messages(6, BACH))], "Cake")
    assert_equal 1, report[:results][:nothing]
    assert_nil read_user_note(1, 123)
  end

  def test_harmful_notes_are_not_saved
    client = BuildMemoryClient.new(answers: [note_json("Is an idiot")], bad_words: ["idiot"])
    report = build_server_memory(client, 1, [HistoryChannel.new(history_messages(6, BACH))], "Cake")
    assert_equal 1, report[:results][:refused]
    assert_nil read_user_note(1, 123)
    assert(LOGS.any? { |line| line.include?("🛡️") })
  end

  def test_a_broken_answer_only_skips_that_person
    channel = HistoryChannel.new(history_messages(6, BACH) + history_messages(6, PIE).map { |m| HistoryMessage.new(m.id + 100, m.author, m.content, m.creation_time) })
    client = BuildMemoryClient.new(answers: ["not json", note_json("Pie note")])
    report = build_server_memory(client, 1, [channel], "Cake")
    assert_equal 1, report[:results][:failed]
    assert_equal 1, report[:results][:built]
  end

  def test_a_channel_it_cant_read_is_skipped
    broken = HistoryChannel.new([], name: "secret", error: RuntimeError.new("Missing Access"))
    good = HistoryChannel.new(history_messages(6, BACH), id: 777)
    report = build_server_memory(BuildMemoryClient.new(answers: [note_json("x")]), 1, [broken, good], "Cake")
    assert_equal 1, report[:read][:channels_skipped]
    assert_equal 1, report[:read][:channels_read]
    assert_equal 1, report[:results][:built]
  end

  def test_the_request_asks_for_json_without_storing
    client = BuildMemoryClient.new(answers: [note_json("x")])
    build_server_memory(client, 1, [HistoryChannel.new(history_messages(6, BACH))], "Cake")
    parameters = client.requests.first
    assert_equal false, parameters[:store]
    assert_equal "json_schema", parameters[:text][:format][:type]
    assert_includes parameters[:instructions], "Cake"
  end

  # --- the command ---

  def test_only_admins
    event = CommandEvent.new(server_with, CommandUser.new(456, "Pie", false))
    assert_nil build_memory_command(event, BuildMemoryClient.new(answers: [note_json("x")]))
    assert_includes event.responses.last, "Only admins"
  end

  def test_only_in_a_server
    event = CommandEvent.new(nil, ADMIN)
    assert_nil build_memory_command(event, BuildMemoryClient.new(answers: [note_json("x")]))
    assert_includes event.responses.last, "only works in a server"
  end

  def test_runs_in_the_background_and_reports
    event = CommandEvent.new(server_with, ADMIN)
    channels = [HistoryChannel.new(history_messages(6, BACH))]
    build_memory_command(event, BuildMemoryClient.new(answers: [note_json("x")]), channels).join
    assert_includes event.responses.first, "Reading old messages"
    assert_includes event.responses.last, "built 1 personality notes"
    assert start_memory_build?(1) # finished, so a new build may start
  end

  def test_one_build_per_server_at_a_time
    start_memory_build?(1)
    event = CommandEvent.new(server_with, ADMIN)
    assert_nil build_memory_command(event, BuildMemoryClient.new(answers: [note_json("x")]))
    assert_includes event.responses.last, "already building"
  end

  def test_report_lists_what_was_skipped
    report = { read: { messages: [1, 2], channels_read: 2, channels_skipped: 1 },
               plan: { too_few: 3, turned_off: 1, over_limit: 0 }, results: Hash.new(0).merge(built: 4, failed: 1) }
    text = build_memory_report_text(report)
    assert_includes text, "built 4 personality notes"
    assert_includes text, "couldn't read 1 channels"
    assert_includes text, "skipped 3 people with fewer than"
    assert_includes text, "1 people failed"
    refute_includes text, "less active"
  end
end
