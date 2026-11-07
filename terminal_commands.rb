# Commands typed in the terminal where the bot runs. To add one, add it to terminal_commands below.
require 'timeout'

# start.bat starts the bot again when it exits with this code
RESTART_EXIT_CODE = 42
BOT_STOP_TIMEOUT_SECONDS = 10

# name => { description: shown in the list of commands, run: what it does }
def terminal_commands(bot)
  {
    "/restart" => { description: "restart the bot (reloads the code and prompts)", run: -> { restart_bot(bot) } }
  }
end

# Reads the terminal in the background, so the bot keeps running while waiting for a command.
# Stops when there is no more input (e.g. the bot was started without a terminal).
def start_terminal_commands(commands, input = $stdin)
  Thread.new do
    while (line = input.gets)
      handle_terminal_line(line, commands)
    end
  end
end

def handle_terminal_line(line, commands)
  name = line.strip.downcase
  return if name.empty?

  command = commands[name]
  return print_unknown_command(line.strip, commands) if command.nil?

  command[:run].call
rescue StandardError => e
  log "⚠️ Terminal command failed (#{e.class})." # A failed command must not stop the terminal
end

def print_unknown_command(text, commands)
  puts "Unknown command: #{text}. Available commands:"
  commands.each { |name, command| puts "  #{name}: #{command[:description]}" }
end

# Disconnect from Discord, then exit with the code start.bat is waiting for.
# exit! because a normal exit only ends this thread, not the bot. Replies still being written are lost.
def restart_bot(bot, exiter = Process.method(:exit!))
  log "🔄 Restarting... (only start.bat starts the bot again; if you ran it another way, start it again yourself)"
  stop_bot_for_restart(bot)
  $stdout.flush # exit! skips this, and the last lines printed would be lost
  exiter.call(RESTART_EXIT_CODE)
end

def stop_bot_for_restart(bot)
  Timeout.timeout(BOT_STOP_TIMEOUT_SECONDS) { bot.stop }
rescue StandardError => e
  log "⚠️ Could not disconnect cleanly (#{e.class}). Restarting anyway."
end
