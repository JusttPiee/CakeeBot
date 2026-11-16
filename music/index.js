import readline from "node:readline";
import { Client, GatewayIntentBits } from "discord.js";
import { parseCommandLine, sendEvent, log } from "./protocol.js";
import { joinChannel, leaveQuietly, leaveAll } from "./voice.js";
import { createCommandQueue } from "./command_queue.js";
import { JOIN_FAILED_REASON } from "./reasons.js";
import { playUrl, pause, resume, stop, setVolume } from "./player.js";

// This program only plays audio in voice channels. It never reads or sends messages.
const client = new Client({
  intents: [GatewayIntentBits.Guilds, GatewayIntentBits.GuildVoiceStates],
});

// Sends one parsed command to the right function.
async function handleCommand(command) {
  switch (command.op) {
    case "join":
      await joinChannel(client, command.guild, command.channel);
      break;
    case "play":
      playUrl(command.guild, command.url, command.volume);
      break;
    case "volume":
      setVolume(command.guild, command.volume);
      break;
    case "pause":
      pause(command.guild);
      break;
    case "resume":
      resume(command.guild);
      break;
    case "stop":
      stop(command.guild);
      break;
    case "leave":
      leaveQuietly(command.guild);
      break;
  }
}

// Reports a command that threw. The failed join keeps the fixed reason text Ruby matches on.
function reportCommandError(command, err) {
  log("command failed:", command.op, err.message);
  const reason = command.op === "join" ? JOIN_FAILED_REASON : `${command.op} error: ${err.message}`;
  sendEvent("failed", { guild: command.guild, reason: reason.slice(0, 200) });
}

// Commands for the same server run one after another (so "play" waits for "join").
const enqueueCommand = createCommandQueue(handleCommand, reportCommandError);

// Reads stdin line by line (Ruby writes one command per line).
function listenToRuby() {
  const lines = readline.createInterface({ input: process.stdin });
  lines.on("line", (line) => {
    const command = parseCommandLine(line);
    if (!command) {
      log("ignored bad line:", line);
      return;
    }
    enqueueCommand(command);
  });
  // stdin closes when Ruby exits: shut down so we never outlive Ruby.
  lines.on("close", shutDown);
}

function shutDown() {
  leaveAll();
  client.destroy();
  process.exit(0);
}

client.once("clientReady", () => sendEvent("ready"));

listenToRuby();
client.login(process.env.DISCORD_BOT_TOKEN).catch((err) => {
  log("login failed:", err.message);
  process.exit(1);
});
