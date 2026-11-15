import {
  joinVoiceChannel,
  createAudioPlayer,
  entersState,
  VoiceConnectionStatus,
} from "@discordjs/voice";
import { sendEvent, log } from "./protocol.js";
import { JOIN_FAILED_REASON } from "./reasons.js";

// One "session" per Discord server (guild): { connection, player, song, leaving }.
// `song` is filled in by player.js while something is playing.
const sessions = new Map();

export function getSession(guildId) {
  return sessions.get(guildId);
}

// Joins a voice channel and creates the audio player for that server.
// Sends "joined" when ready, or "failed" if the connection does not come up.
export async function joinChannel(client, guildId, channelId) {
  leaveQuietly(guildId);

  const guild = await client.guilds.fetch(guildId);
  const connection = joinVoiceChannel({
    guildId,
    channelId,
    adapterCreator: guild.voiceAdapterCreator,
    selfDeaf: true,
  });
  const player = makePlayer();
  connection.subscribe(player);

  const session = { connection, player, song: null, leaving: false };
  sessions.set(guildId, session);
  watchConnection(guildId, session);

  try {
    await entersState(connection, VoiceConnectionStatus.Ready, 20_000);
    sendEvent("joined", { guild: guildId });
  } catch {
    leaveQuietly(guildId);
    sendEvent("failed", { guild: guildId, reason: JOIN_FAILED_REASON });
  }
}

// Creates an audio player that always has an "error" listener.
// Without one, Node throws and the whole program crashes when a stream fails
// after player.js has already stopped listening for that song.
export function makePlayer() {
  const player = createAudioPlayer();
  player.on("error", (err) => log("player error:", err.message));
  return player;
}

// Leaves every server (used when the program shuts down), killing yt-dlp/ffmpeg.
export function leaveAll() {
  for (const guildId of [...sessions.keys()]) leaveQuietly(guildId);
}

// Leaves because Ruby asked us to. No "disconnected" event is sent.
export function leaveQuietly(guildId) {
  const session = sessions.get(guildId);
  if (!session) return;
  session.leaving = true;
  sessions.delete(guildId);
  session.song?.kill();
  session.player.stop(true);
  if (session.connection.state.status !== VoiceConnectionStatus.Destroyed) {
    session.connection.destroy();
  }
}

// Watches for the bot being kicked, moved out, or losing the connection.
function watchConnection(guildId, session) {
  const { connection } = session;

  connection.on(VoiceConnectionStatus.Disconnected, async () => {
    // Being moved to another channel looks like a short disconnect; give it 5s to reconnect.
    try {
      await Promise.race([
        entersState(connection, VoiceConnectionStatus.Signalling, 5_000),
        entersState(connection, VoiceConnectionStatus.Connecting, 5_000),
      ]);
    } catch {
      if (connection.state.status !== VoiceConnectionStatus.Destroyed) connection.destroy();
    }
  });

  connection.on(VoiceConnectionStatus.Destroyed, () => {
    if (session.leaving) return;
    log("voice connection destroyed for", guildId);
    sessions.delete(guildId);
    session.song?.kill();
    session.player.stop(true);
    sendEvent("disconnected", { guild: guildId });
  });
}
