require_relative "web_test_helper"

class WebUserNotesTest < WebApiTest
  # Write a note file straight to the test memory, like the bot would
  def save_note(user_id, name:, description: "", personality: "", facts: [], off: false)
    note = { name: name, description: description, personality: personality, remembered: facts, personality_off: off }
    write_user_note("111", user_id, note)
  end

  def test_lists_people_with_fact_counts
    save_note("5", name: "Bach", description: "likes Valorant", facts: ["[2026-11-04] no anime"])
    save_note("6", name: "", off: true) # what !forgetme leaves
    api :get, "/api/servers/111/users"
    assert_equal [{ "id" => "5", "name" => "Bach", "description" => "likes Valorant", "fact_count" => 1, "personality_off" => false },
                  { "id" => "6", "name" => "", "description" => "", "fact_count" => 0, "personality_off" => true }], json
  end

  def test_sorts_people_by_name_with_blank_notes_last
    save_note("1", name: "", off: true)
    save_note("2", name: "zed")
    save_note("3", name: "Anna")
    api :get, "/api/servers/111/users"
    assert_equal %w[3 2 1], json.map { |person| person["id"] }
  end

  def test_shows_one_note_with_fact_ids
    save_note("5", name: "Bach", personality: "Plays most nights", facts: ["[2026-11-04] no anime"])
    api :get, "/api/servers/111/users/5"
    assert_equal "Plays most nights", json["personality"]
    assert_equal "2026-11-04", json["facts"][0]["date"]
    assert_equal "no anime", json["facts"][0]["text"]
    assert_match(/\A[0-9a-f]{8}\z/, json["facts"][0]["id"])
  end

  def test_saving_never_drops_a_fact_added_after_the_form_was_opened # Review Focus 1
    save_note("5", name: "Bach", facts: ["[2026-11-04] no anime"])
    append_remembered_fact("111", "5", "Bach", "added by the bot meanwhile")
    api :put, "/api/servers/111/users/5", { description: "new", personality: "## sneaky\nnew text", personality_off: false }
    note = read_user_note("111", "5")
    assert_equal 2, note[:remembered].length
    assert_equal "new", note[:description]
    assert_equal "sneaky\nnew text", note[:personality] # headings removed
    assert_includes read_memory_file("111", "MEMORY.md"), "Bach (5): new" # index rebuilt
  end

  def test_turning_personality_off_clears_it
    save_note("5", name: "Bach", description: "d", personality: "p", facts: ["[2026-11-04] kept"])
    api :put, "/api/servers/111/users/5", { description: "d", personality: "p", personality_off: true }
    note = read_user_note("111", "5")
    assert_equal ["", "", true, 1], [note[:description], note[:personality], note[:personality_off], note[:remembered].length]
  end

  def test_turning_personality_back_on_is_logged
    save_note("6", name: "", off: true)
    api :put, "/api/servers/111/users/6", { description: "", personality: "", personality_off: false }
    assert_equal false, read_user_note("111", "6")[:personality_off]
    assert(LOGS.any? { |line| line.include?("turned personality notes back on for user 6") })
  end

  def test_deleting_removes_the_file_and_does_not_opt_out
    save_note("5", name: "Bach", facts: ["[2026-11-04] x"])
    update_tidy_state("111", "5", tidied: "abc")
    api :delete, "/api/servers/111/users/5"
    assert_equal({ "ok" => true }, json)
    assert_nil read_user_note("111", "5")
    assert_empty tidy_state_of("111", "5")
    refute_includes read_memory_file("111", "MEMORY.md").to_s, "Bach"
  end

  def test_adds_changes_and_removes_a_fact
    save_note("5", name: "Bach")
    api :post, "/api/servers/111/users/5/facts", { text: "mains  Jett" }
    id = json["facts"][0]["id"]
    assert_equal "mains Jett", json["facts"][0]["text"]
    api :put, "/api/servers/111/items/#{id}", { text: "mains Sage" }
    assert_equal 200, last_response.status
    new_id = personal_memory_items("111")[0][:id]
    assert_includes read_memory_file("111", "MEMORY.md"), "mains Sage"
    api :delete, "/api/servers/111/items/#{new_id}"
    assert_empty read_user_note("111", "5")[:remembered]
  end

  def test_bad_input_is_refused
    save_note("5", name: "Bach")
    api :post, "/api/servers/111/users/5/facts", { text: "   " }
    assert_equal 422, last_response.status
    api :post, "/api/servers/111/users/5/facts", { text: "x" * (REMEMBER_FACT_MAX_CHARS + 1) }
    assert_equal 422, last_response.status
    api :post, "/api/servers/111/users/77/facts", { text: "nobody has this note" }
    assert_equal 404, last_response.status
    api :get, "/api/servers/111/users/77"
    assert_equal 404, last_response.status
    api :get, "/api/servers/111/users/..%2F..%2Fx" # Review Focus 2
    assert_equal 404, last_response.status
    api :delete, "/api/servers/111/items/zzzzzzzz"
    assert_equal 404, last_response.status
    api :put, "/api/servers/111/items/00000000", { text: "no such item" }
    assert_equal 404, last_response.status
    api :put, "/api/servers/111/users/5", "not an object"
    assert_equal 400, last_response.status
    assert_empty read_user_note("111", "5")[:remembered]
  end
end
