require_relative "test_helper"
require "stringio"
require_relative "../terminal_commands"

# Commands typed in the terminal where the bot runs, like /restart
class TerminalCommandsTest < Minitest::Test
  class FakeBot
    attr_reader :stopped

    def stop = @stopped = true
  end

  class BrokenBot
    def stop = raise(IOError, "already closed")
  end

  def setup
    LOGS.clear
    @ran = []
    @commands = { "/test" => { description: "a test command", run: -> { @ran << "/test" } } }
  end

  def test_a_known_command_runs
    handle_terminal_line("/test\n", @commands)
    assert_equal ["/test"], @ran
  end

  def test_case_and_spaces_do_not_matter
    handle_terminal_line("  /TEST  \n", @commands)
    assert_equal ["/test"], @ran
  end

  def test_an_empty_line_does_nothing
    out, = capture_io { handle_terminal_line("   \n", @commands) }
    assert_empty out
    assert_empty @ran
  end

  def test_an_unknown_command_lists_the_available_ones
    out, = capture_io { handle_terminal_line("/nope\n", @commands) }
    assert_includes out, "Unknown command: /nope"
    assert_includes out, "/test: a test command"
    assert_empty @ran
  end

  def test_a_failing_command_does_not_stop_the_terminal
    commands = { "/bad" => { description: "fails", run: -> { raise IOError, "boom" } } }
    handle_terminal_line("/bad", commands)
    assert_includes LOGS.last, "IOError"
  end

  def test_lines_are_read_until_the_input_ends
    start_terminal_commands(@commands, StringIO.new("/test\n/test\n")).join
    assert_equal ["/test", "/test"], @ran
  end

  def test_restart_is_in_the_command_list
    assert_includes terminal_commands(FakeBot.new).keys, "/restart"
  end

  def test_restart_stops_the_bot_then_exits_with_the_restart_code
    bot = FakeBot.new
    codes = []
    restart_bot(bot, ->(code) { codes << code })
    assert bot.stopped
    assert_equal [RESTART_EXIT_CODE], codes
  end

  # exit! doesn't flush, so printed lines would be lost without this
  def test_restart_flushes_the_terminal_before_exiting
    output = StringIO.new
    flushed_before_exit = nil
    def output.flush = (@flushed = true; super)
    def output.flushed? = @flushed
    original = $stdout
    $stdout = output
    restart_bot(FakeBot.new, ->(_code) { flushed_before_exit = output.flushed? })
    $stdout = original
    assert flushed_before_exit
  end

  def test_restart_still_exits_if_stopping_fails
    codes = []
    restart_bot(BrokenBot.new, ->(code) { codes << code })
    assert_equal [RESTART_EXIT_CODE], codes
    assert_includes LOGS.last, "IOError"
  end

  def test_start_bat_restarts_on_the_restart_code
    start_bat = File.read(File.join(__dir__, "..", "start.bat"))
    assert_includes start_bat, "if %errorlevel%==#{RESTART_EXIT_CODE}"
  end
end
