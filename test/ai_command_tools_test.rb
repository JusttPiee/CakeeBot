require_relative "test_helper"
require_relative "../config"
require_relative "../tool_list"

class ToolPostChannel
  attr_reader :sent

  def initialize
    @sent = []
  end

  def send_message(*args)
    @sent << args
    nil
  end
end

class ToolMember
  attr_reader :id

  def initialize(admin)
    @admin = admin
    @id = 5
  end

  def permission?(_permission) = @admin
end

class AiCommandToolsTest < Minitest::Test
  def command_context(silent: false, admin: true, music: nil)
    { silent: silent, member: ToolMember.new(admin), server: nil, post_channel: ToolPostChannel.new, music: music,
      request_message_id: 99, command_labels: [], requester_id: 5, avatar_url: nil }
  end

  def test_tools_are_registered
    assert_equal [], %w[show_help music manage_messages] - available_tools.keys
  end

  def test_silent_refuses_every_command_tool
    ctx = command_context(silent: true)
    %w[run_show_help run_music run_manage_messages].each do |name|
      assert_equal "Not available in a private question.", send(name, {}, ctx)
    end
  end

  def test_show_help_posts_and_labels
    ctx = command_context
    assert_equal "Showed the help page Music.", run_show_help({ "category" => "music" }, ctx)
    assert_equal 1, ctx[:post_channel].sent.length
    assert_equal ["[showed help: Music]"], ctx[:command_labels]
  end

  def test_show_help_unknown_category_is_the_overview
    ctx = command_context
    assert_equal "Showed the help page Overview.", run_show_help({ "category" => "nonsense" }, ctx)
    assert_equal "Showed the help page Overview.", run_show_help({}, command_context)
  end

  def test_music_unavailable_gets_no_label
    ctx = command_context
    assert_equal MUSIC_UNAVAILABLE_TEXT, run_music({ "action" => "skip", "query" => "", "level" => -1 }, ctx)
    assert_empty ctx[:command_labels]
  end

  # Replaces music_ai_action on this test only, and records what run_music passed to it
  def stub_music_action(result)
    calls = []
    define_singleton_method(:music_ai_action) do |*args, **options|
      calls << [args, options]
      result
    end
    calls
  end

  def test_music_passes_the_context_and_arguments
    ctx = command_context(music: :controller)
    ctx[:server] = :server
    calls = stub_music_action("Skipped.")
    assert_equal "Skipped.", run_music({ "action" => "set_volume", "query" => "", "level" => -1 }, ctx)
    assert_equal [[[:controller, :server, ctx[:member], ctx[:post_channel], "set_volume"], { query: "", level: nil }]], calls
    assert_equal ["[music: Skipped.]"], ctx[:command_labels]
  end

  def test_music_passes_the_level_and_query_and_labels_the_queue
    ctx = command_context(music: :controller)
    calls = stub_music_action("Now playing: a")
    run_music({ "action" => "queue", "query" => "song", "level" => 40 }, ctx)
    assert_equal({ query: "song", level: 40 }, calls.first[1])
    assert_equal ["[music: showed the queue]"], ctx[:command_labels]
  end

  def test_music_keeps_a_non_numeric_level_raw
    calls = stub_music_action("Refused: give a volume from 0 to 100.")
    run_music({ "action" => "set_volume", "query" => "", "level" => "loud" }, command_context)
    assert_equal "loud", calls.first[1][:level]
    assert_nil music_level("")
  end

  def test_music_refusal_from_the_action_gets_no_label
    ctx = command_context
    stub_music_action("Refused: join the voice channel first.")
    run_music({ "action" => "skip", "query" => "", "level" => -1 }, ctx)
    assert_empty ctx[:command_labels]
  end

  def test_manage_messages_user_id_zero_means_everyone
    ctx = command_context
    result = run_manage_messages({ "amount" => 4, "from_user_id" => "0" }, ctx)
    assert_equal "Asked <@5> to confirm deleting 4 messages with a button. Nothing is deleted until they press Delete.", result
    assert_equal ["[asked to confirm: delete 4 messages]"], ctx[:command_labels]
  end

  def test_music_labels
    ctx = command_context
    add_music_label(ctx, "queue", "Now playing: a\nNext: b")
    add_music_label(ctx, "skip", "Skipped.")
    add_music_label(ctx, "skip", "Refused: join the voice channel first.")
    assert_equal ["[music: showed the queue]", "[music: Skipped.]"], ctx[:command_labels]
  end

  def test_music_level_minus_one_is_nil
    assert_nil music_level(-1)
    assert_nil music_level(nil)
    assert_equal 40, music_level(40)
  end

  def test_manage_messages_refuses_non_admin
    ctx = command_context(admin: false)
    assert_equal "Refused: only admins can delete messages.", run_manage_messages({ "amount" => 5, "from_user_id" => "" }, ctx)
    assert_empty ctx[:post_channel].sent
    assert_empty ctx[:command_labels]
  end

  def test_manage_messages_cleans_and_checks_arguments
    ctx = command_context
    assert_includes run_manage_messages({ "amount" => 5, "from_user_id" => "<@12>" }, ctx), "from <@12>"
    assert_equal "Refused: from_user_id must be a user id.", run_manage_messages({ "amount" => 5, "from_user_id" => "abc" }, command_context)
    assert_equal "Refused: amount must be 1 to #{CLEAR_MAX_MESSAGES}.", run_manage_messages({ "amount" => 500, "from_user_id" => "" }, command_context)
  end

  def test_manage_messages_posts_confirm_and_labels
    ctx = command_context
    result = run_manage_messages({ "amount" => 20, "from_user_id" => "" }, ctx)
    assert_equal "Asked <@5> to confirm deleting 20 messages with a button. Nothing is deleted until they press Delete.", result
    assert_equal 1, ctx[:post_channel].sent.length
    assert_equal ["[asked to confirm: delete 20 messages]"], ctx[:command_labels]
  end

  def test_manage_messages_label_with_a_user
    ctx = command_context
    run_manage_messages({ "amount" => 3, "from_user_id" => "12" }, ctx)
    assert_equal ["[asked to confirm: delete 3 messages from <@12>]"], ctx[:command_labels]
  end

  def test_long_labels_are_cut
    ctx = { command_labels: [] }
    add_command_label(ctx, "music: " + "x" * 200)
    assert_equal COMMAND_LABEL_MAX_CHARS, ctx[:command_labels].first.length
    assert ctx[:command_labels].first.end_with?("…]")
  end

  def test_no_label_list_is_fine
    add_command_label({}, "music: x")
  end
end
