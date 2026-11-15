import { test } from "node:test";
import assert from "node:assert/strict";
import { parseCommandLine, eventLine } from "./protocol.js";

test("play line is parsed", () => {
  assert.deepEqual(parseCommandLine('{"op":"play","guild":"1","url":"u"}'), { op: "play", guild: "1", url: "u" });
});
test("bad lines give null", () => {
  assert.equal(parseCommandLine("not json"), null);
  assert.equal(parseCommandLine('{"op":"dance","guild":"1"}'), null);
  assert.equal(parseCommandLine('{"op":"play"}'), null);
});
test("event line is one JSON line", () => {
  assert.equal(eventLine("failed", { guild: "1", reason: "x" }), '{"event":"failed","guild":"1","reason":"x"}\n');
});
