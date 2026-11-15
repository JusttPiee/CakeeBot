import { createAudioResource, StreamType, AudioPlayerStatus } from "@discordjs/voice";
import { openStream } from "./stream.js";
import { getSession } from "./voice.js";
import { sendEvent, log } from "./protocol.js";
import { NOT_CONNECTED_REASON } from "./reasons.js";

// Starts playing the audio of `url` in the server's voice channel.
// Sends "started", then "finished" (or "failed" if the song cannot play).
export function playUrl(guildId, url) {
  const session = getSession(guildId);
  if (!session) {
    sendEvent("failed", { guild: guildId, reason: NOT_CONNECTED_REASON });
    return;
  }
  // A new song replaces the old one; the old one is dropped without any event.
  session.song?.kill();

  const song = newSong(guildId, session);
  session.song = song;

  const stream = openStream(url);
  song.stream = stream;
  stream.on("error", (err) => endSong(song, "failed", err.message));

  const resource = createAudioResource(stream, { inputType: StreamType.OggOpus });
  session.player.play(resource);
}

export function pause(guildId) {
  getSession(guildId)?.player.pause();
}

export function resume(guildId) {
  getSession(guildId)?.player.unpause();
}

// Stops the current song. Always ends with a "finished" event (if a song was playing).
export function stop(guildId) {
  const session = getSession(guildId);
  // Silent when nothing is active: a natural "finished" may already be on its
  // way, and a second one would make Ruby skip a song.
  if (!session?.song) return;
  endSong(session.song, "finished");
  session.player.stop(true);
}

// Creates the bookkeeping object for one song and listens to the player.
export function newSong(guildId, session) {
  const song = { guildId, session, stream: null, started: false, done: false };

  const onStateChange = (oldState, newState) => {
    if (newState.status === AudioPlayerStatus.Playing && !song.started) {
      song.started = true;
      sendEvent("started", { guild: guildId });
    }
    if (newState.status === AudioPlayerStatus.Idle && !song.done) {
      // Reaching "idle" without ever playing means there was no audio at all.
      if (song.started) endSong(song, "finished");
      else endSong(song, "failed", "no audio was produced");
    }
  };
  const onError = (err) => endSong(song, "failed", err.message);

  // Kills yt-dlp/ffmpeg and stops listening, without sending any event.
  song.kill = () => {
    song.done = true;
    song.stream?.destroy();
    session.player.off("stateChange", onStateChange);
    session.player.off("error", onError);
  };

  session.player.on("stateChange", onStateChange);
  session.player.on("error", onError);
  return song;
}

// Ends a song exactly once: kills yt-dlp/ffmpeg, then sends one event.
export function endSong(song, eventName, reason) {
  if (song.done) return;
  song.kill();
  // Stop the player too, so it goes Idle and drops the broken resource.
  song.session.player.stop(true);
  if (song.session.song === song) song.session.song = null;
  if (eventName === "failed") {
    log("song failed:", reason);
    sendEvent("failed", { guild: song.guildId, reason: String(reason).slice(0, 200) });
  } else {
    sendEvent("finished", { guild: song.guildId });
  }
}
