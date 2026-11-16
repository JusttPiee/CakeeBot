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

# A terminal that says "nothing typed yet" a few times before each line, like a real window.
# It remembers whether gets was ever called while nothing was typed.
class SlowTerminal
  attr_reader :gets_while_empty

  def initialize(lines, empty_checks)
    @lines = lines
    @empty_checks = empty_checks
    @left = empty_checks
    @typed = false # becomes true once wait_readable reported a typed line
    @gets_while_empty = false
  end

  def tty? = true

  # nil (nothing typed) a few times, then self (a line is waiting)
  def wait_readable(_seconds)
    return nil if (@left -= 1).positive?

    @left = @empty_checks
    @typed = true
    self
  end

  def gets
    @gets_while_empty = true unless @typed
    @typed = false
    @lines.shift
  end
end

  # On Windows a thread waiting inside gets never wakes up once Ruby starts a child process
  # (Node, yt-dlp), so gets may only be called when something was typed
  def test_gets_is_only_called_after_something_was_typed
    terminal = SlowTerminal.new(["/test\n", "/test\n"], 3)
    start_terminal_commands(@commands, terminal).join
    assert_equal ["/test", "/test"], @ran
    refute terminal.gets_while_empty
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

  def test_restart_stops_the_music_bridge_too
    bridge = Struct.new(:stopped) { def stop = (self.stopped = true) }.new(false)
    restart_bot(FakeBot.new, ->(_code) {}, bridge)
    assert bridge.stopped
  end

  def test_restart_still_exits_if_the_music_bridge_fails_to_stop
    bridge = Object.new
    def bridge.stop = raise(IOError, "closed")
    codes = []
    restart_bot(FakeBot.new, ->(code) { codes << code }, bridge)
    assert_equal [RESTART_EXIT_CODE], codes
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
