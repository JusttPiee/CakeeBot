require_relative "test_helper"
require_relative "../music_panel"

# A pretend Discord message: remembers edits, can be told to fail like a deleted message
class PanelMessage
  attr_reader :edits

  def initialize
    @edits = []
    @fail = false
  end

  def fail_edits!
    @fail = true
  end

  def edit(content, embeds = nil, components = nil)
    raise Discordrb::Errors::UnknownMessage.new("gone") if @fail
    @edits << [content, embeds, components]
  end
end

# A pretend channel: remembers the messages it sent
class PanelChannel
  attr_reader :sent

  def initialize(send_delay = 0)
    @sent = []
    @send_delay = send_delay
  end

  def send_message(content, tts = false, embed = nil, attachments = nil, allowed_mentions = nil, message_reference = nil, components = nil)
    sleep @send_delay
    @sent << PanelMessage.new
    @sent.last
  end
end

class MusicPanelTest < Minitest::Test
  def test_durations
    assert_equal "3:45", format_duration(225)
    assert_equal "1:02:03", format_duration(3723)
    assert_equal "?", format_duration(nil)
  end

  def test_embed_shows_playlist_and_queue
    track = MusicTrack.new(title: "Song", artist: "Singer", duration: 225, url: "https://y/1", requester_id: 9, playlist_name: "Lofi")
    embed = music_panel_embed(track, 12, false)
    assert_includes embed.description, "Lofi"
    assert_includes embed.description, "12 songs in queue"
    assert_includes embed.description, "<@9>"
  end

  def test_embed_title_follows_pause_state
    track = MusicTrack.new(title: "Song", url: "https://y/1")
    assert_includes music_panel_embed(track, 0, false).title, "Now playing"
    assert_includes music_panel_embed(track, 0, true).title, "Paused"
  end

  def test_embed_link_survives_brackets_in_title
    track = MusicTrack.new(title: "Hi [live] (2)", url: "https://y/1?a=(b)")
    description = music_panel_embed(track, 0, false).description
    assert_includes description, "[Hi (live) (2)](https://y/1?a=%28b%29)"
  end

  def test_embed_shows_the_volume
    track = MusicTrack.new(title: "Song", url: "https://y/1")
    assert_includes music_panel_embed(track, 0, false, 40).description, "🔊 40%"
    refute_includes music_panel_embed(track, 0, false).description, "%"
  end

  def test_volume_loop_and_shuffle_buttons_are_on_a_second_row
    rows = music_panel_view(false).to_a
    assert_equal %w[music:voldown music:volup music:loop music:shuffle], rows[1][:components].map { |c| c[:custom_id] }
  end

  # Every button has an emoji. Text-style symbols need U+FE0F, or Discord may refuse the panel
  def test_every_button_has_an_emoji
    buttons = music_panel_view(false).to_a.flat_map { |row| row[:components] }
    emojis = buttons.to_h { |button| [button[:custom_id], button.dig(:emoji, :name)] }
    assert_equal({ "music:toggle" => "⏸\u{FE0F}", "music:skip" => "⏭\u{FE0F}", "music:skipplaylist" => "⏩",
                   "music:queue" => "📜", "music:clearqueue" => "🗑\u{FE0F}", "music:voldown" => "🔉",
                   "music:volup" => "🔊", "music:loop" => "➡\u{FE0F}", "music:shuffle" => "🔀" }, emojis)
    assert_equal "▶\u{FE0F}", music_panel_view(true).to_a.first[:components].first.dig(:emoji, :name)
  end

  def test_second_row_labels_have_no_emoji_in_the_text
    labels = music_panel_view(false).to_a[1][:components].map { |c| c[:label] }
    assert_equal ["-#{MUSIC_VOLUME_STEP}%", "+#{MUSIC_VOLUME_STEP}%", "Loop: Off", "Shuffle"], labels
  end

  # The Loop button shows the mode it is in now
  def test_loop_button_follows_the_mode
    { off: ["Loop: Off", "➡\u{FE0F}"], song: ["Loop: Song", "🔂"], queue: ["Loop: Queue", "🔁"] }.each do |mode, (label, emoji)|
      button = music_panel_view(false, mode).to_a[1][:components].find { |c| c[:custom_id] == "music:loop" }
      assert_equal [label, emoji], [button[:label], button.dig(:emoji, :name)], mode
    end
  end

  def test_embed_shows_the_loop_mode_only_when_on
    song = MusicTrack.new(title: "a", requester_id: 5)
    refute_includes music_panel_embed(song, 0, false, 50, :off).description, "Loop"
    assert_includes music_panel_embed(song, 0, false, 50, :song).description, "🔂 Looping this song"
    assert_includes music_panel_embed(song, 0, false, 50, :queue).description, "🔁 Looping the queue"
  end

  def test_buttons_and_toggle_label
    ids = music_panel_view(false).to_a.first[:components].map { |c| c[:custom_id] }
    assert_equal %w[music:toggle music:skip music:skipplaylist music:queue music:clearqueue], ids
    assert_equal "Resume", music_panel_view(true).to_a.first[:components].first[:label]
    assert_equal "Pause", music_panel_view(false).to_a.first[:components].first[:label]
  end

  def test_queue_text_cuts_at_limit
    waiting = (1..20).map { |i| MusicTrack.new(title: "s#{i}", duration: 60) }
    text = music_queue_text(nil, waiting, 15)
    assert_includes text, "15. s15"
    assert_includes text, "...and 5 more"
  end

  def test_queue_text_when_empty
    assert_equal "The queue is empty.", music_queue_text(nil, [])
  end

  def test_show_edits_the_same_message
    channel = PanelChannel.new
    poster = MusicPanelPoster.new
    2.times { poster.show(1, channel, music_stopped_embed, music_panel_view(false)) }
    assert_equal 1, channel.sent.length
    assert_equal 1, channel.sent.first.edits.length
  end

  def test_show_reposts_when_old_message_is_gone
    channel = PanelChannel.new
    poster = MusicPanelPoster.new
    poster.show(1, channel, music_stopped_embed, music_panel_view(false))
    channel.sent.first.fail_edits!
    poster.show(1, channel, music_stopped_embed, music_panel_view(false))
    assert_equal 2, channel.sent.length
  end

  def test_concurrent_shows_send_only_one_message
    channel = PanelChannel.new(0.05)
    poster = MusicPanelPoster.new
    threads = 5.times.map { Thread.new { poster.show(1, channel, music_stopped_embed, music_panel_view(false)) } }
    threads.each(&:join)
    assert_equal 1, channel.sent.length
  end

  def test_stop_removes_buttons_and_forgets
    channel = PanelChannel.new
    poster = MusicPanelPoster.new
    poster.show(1, channel, music_stopped_embed, music_panel_view(false))
    poster.stop(1)
    assert_equal [], channel.sent.first.edits.last[2].to_a
    poster.show(1, channel, music_stopped_embed, music_panel_view(false))
    assert_equal 2, channel.sent.length
  end

  def test_stop_without_panel_does_nothing
    MusicPanelPoster.new.stop(5)
  end
end
