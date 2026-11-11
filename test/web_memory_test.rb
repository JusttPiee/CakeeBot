require_relative "web_test_helper"

class WebMemoryTest < WebApiTest
  def test_lists_general_notes_newest_first
    append_general_note("111", "5", "Bach", "6", "Pie", "is bad at Valorant", Time.new(2026, 11, 7))
    append_general_note("111", "6", "Pie", "5", "Bach", "owes me a drink", Time.new(2026, 11, 9))
    api :get, "/api/servers/111/general"
    assert_equal ["owes me a drink", "is bad at Valorant"], json.map { |note| note["text"] }
    assert_equal ["6", "Pie", "5", "Bach"], json[0].values_at("author_id", "author_name", "subject_id", "subject_name")
    assert_equal "2026-11-09", json[0]["date"]
    assert_match(/\A[0-9a-f]{8}\z/, json[0]["id"])
  end

  def test_a_general_note_can_be_changed_through_the_items_route
    append_general_note("111", "5", "Bach", "6", "Pie", "is bad at Valorant", Time.new(2026, 11, 7))
    api :get, "/api/servers/111/general"
    api :put, "/api/servers/111/items/#{json[0]['id']}", { text: "is great at Valorant" }
    api :get, "/api/servers/111/general"
    assert_equal ["is great at Valorant"], json.map { |note| note["text"] }
    assert_equal "5", json[0]["author_id"] # still Bach's opinion
  end

  def test_lists_events_and_marks_past_ones
    save_event_note("111", "Old Cup", "2020-01-01", "done")
    save_event_note("111", "Valorant Cup", "2099-11-21 20:00", "bring snacks")
    api :get, "/api/servers/111/events"
    assert_equal [["old-cup", true], ["valorant-cup", false]], json.map { |event| [event["slug"], event["past"]] }
    assert_equal ["Valorant Cup", "2099-11-21 20:00", "bring snacks"], json[1].values_at("title", "when", "details")
  end

  def test_renaming_an_event_moves_its_file
    save_event_note("111", "Valorant Cup", "2099-11-21 20:00", "bring snacks")
    api :put, "/api/servers/111/events/valorant-cup", { title: "Valo Night", when: "2099-11-22", details: "new plan" }
    assert_equal "valo-night", json["slug"]
    assert_equal ["events/valo-night.md"], list_memory_files("111", "events")
    assert_includes read_memory_file("111", "MEMORY.md"), "Valo Night"
  end

  def test_a_bad_event_date_is_refused_and_nothing_changes
    save_event_note("111", "Valorant Cup", "2099-11-21 20:00", "bring snacks")
    api :put, "/api/servers/111/events/valorant-cup", { title: "Valorant Cup", when: "next friday", details: "x" }
    assert_equal 422, last_response.status
    assert_includes json["error"], "YYYY-MM-DD"
    api :put, "/api/servers/111/events/valorant-cup", { title: "  ", when: "2099-11-22", details: "x" }
    assert_equal 422, last_response.status
    assert_equal "bring snacks", list_event_notes("111")[0][:details]
  end

  def test_renaming_an_event_never_overwrites_another_event
    save_event_note("111", "Valorant Cup", "2099-11-21 20:00", "bring snacks")
    save_event_note("111", "Movie Night", "2099-12-01", "popcorn")
    api :put, "/api/servers/111/events/movie-night", { title: "Valorant Cup", when: "2099-12-01", details: "popcorn" }
    assert_equal 422, last_response.status
    assert_equal 2, list_event_notes("111").length
  end

  def test_deletes_an_event_and_refuses_odd_slugs
    save_event_note("111", "Valorant Cup", "2099-11-21 20:00", "x")
    api :delete, "/api/servers/111/events/a..b" # ".." is never part of a file name we made
    assert_equal 404, last_response.status
    api :delete, "/api/servers/111/events/no-such-event"
    assert_equal 404, last_response.status
    api :delete, "/api/servers/111/events/valorant-cup"
    assert_empty list_memory_files("111", "events")
  end

  def test_lists_and_deletes_channel_summaries
    write_channel_summary("111", "900", "They planned a Valorant night.", "123", Time.new(2026, 11, 4, 14, 2))
    write_channel_summary("111", "777", "A channel that was deleted.", "124", Time.new(2026, 11, 5, 9, 0))
    api :get, "/api/servers/111/summaries"
    assert_equal [{ "channel_id" => "777", "channel_name" => "", "updated" => "2026-11-05 09:00", "text" => "A channel that was deleted." },
                  { "channel_id" => "900", "channel_name" => "general", "updated" => "2026-11-04 14:02", "text" => "They planned a Valorant night." }], json
    api :delete, "/api/servers/111/summaries/900"
    assert_equal ["channels/777.md"], list_memory_files("111", "channels")
    api :delete, "/api/servers/111/summaries/900"
    assert_equal 404, last_response.status
  end

  def test_lists_the_recent_activity_newest_first
    RECENT_ACTIVITY.clear
    record_recent_exchange(111, { id: "900", name: "general", public: true }, "5", "Piee", "explain Natlan", "Natlan is fire", Time.now - 60)
    record_recent_tag(111, { id: "901", name: "secret", public: false }, "1333", "Citlali [bot]", "hey Cake")
    api :get, "/api/servers/111/recent"
    assert_equal [["tagged", "secret", false, "Citlali [bot]", "hey Cake", nil],
                  ["exchange", "general", true, "Piee", "explain Natlan", "Natlan is fire"]],
                 json.map { |entry| entry.values_at("kind", "channel_name", "public", "speaker_name", "text", "answer") }
    assert_match(/\A\d{4}-\d{2}-\d{2}T/, json[0]["time"])
  ensure
    RECENT_ACTIVITY.clear
  end
end
