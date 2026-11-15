import { test } from "node:test";
import assert from "node:assert/strict";
import { makePlayer } from "./voice.js";
import { newSong, endSong } from "./player.js";

// A failed song must not crash Node when the player reports an error afterwards.
test("player error after a failed song does not throw", () => {
  const written = [];
  const realWrite = process.stdout.write;
  process.stdout.write = (text) => { written.push(text); return true; };
  try {
    const player = makePlayer();
    const session = { player, song: null };
    const song = newSong("1", session);
    session.song = song;
    endSong(song, "failed", "boom");
    assert.doesNotThrow(() => player.emit("error", new Error("late stream error")));
  } finally {
    process.stdout.write = realWrite;
  }
  assert.equal(written.join(""), '{"event":"failed","guild":"1","reason":"boom"}\n');
});
