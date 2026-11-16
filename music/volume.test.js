import { test } from "node:test";
import assert from "node:assert/strict";
import { clampVolume, volumeGain } from "./volume.js";
import { parseCommandLine } from "./protocol.js";
import { ffmpegArgs } from "./stream.js";

test("volume is kept between 0 and 100 and rounded", () => {
  assert.equal(clampVolume(30), 30);
  assert.equal(clampVolume(150), 100);
  assert.equal(clampVolume(-5), 0);
  assert.equal(clampVolume(42.6), 43);
});

test("a missing or broken volume falls back to the default", () => {
  assert.equal(clampVolume(undefined, 50), 50);
  assert.equal(clampVolume("loud", 50), 50);
});

test("volume 50 is half the original loudness", () => {
  assert.equal(volumeGain(50), 0.5);
  assert.equal(volumeGain(100), 1);
});

test("the volume command is parsed", () => {
  assert.deepEqual(parseCommandLine('{"op":"volume","guild":"1","volume":30}'), { op: "volume", guild: "1", volume: 30 });
});

test("ffmpeg outputs raw PCM so the volume can change mid-song", () => {
  const args = ffmpegArgs();
  assert.deepEqual(args.slice(args.indexOf("-f"), args.indexOf("-f") + 2), ["-f", "s16le"]);
  assert.ok(args.includes("48000"));
  assert.ok(!args.includes("libopus"));
});
