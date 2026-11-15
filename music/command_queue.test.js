import { test } from "node:test";
import assert from "node:assert/strict";
import { createCommandQueue } from "./command_queue.js";

const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

test("play after a slow join for the same guild waits for the join", async () => {
  const log = [];
  const enqueue = createCommandQueue(async (command) => {
    if (command.op === "join") await wait(50);
    log.push(command.op);
  }, () => {});
  enqueue({ op: "join", guild: "1" });
  await enqueue({ op: "play", guild: "1" });
  assert.deepEqual(log, ["join", "play"]);
});

test("two guilds do not block each other", async () => {
  const log = [];
  const enqueue = createCommandQueue(async (command) => {
    if (command.guild === "1") await wait(50);
    log.push(command.guild);
  }, () => {});
  const slow = enqueue({ op: "join", guild: "1" });
  await enqueue({ op: "join", guild: "2" });
  assert.deepEqual(log, ["2"]);
  await slow;
  assert.deepEqual(log, ["2", "1"]);
});

test("an error is reported and the next command still runs", async () => {
  const errors = [];
  const ran = [];
  const enqueue = createCommandQueue(async (command) => {
    if (command.op === "join") throw new Error("boom");
    ran.push(command.op);
  }, (command, err) => errors.push(err.message));
  enqueue({ op: "join", guild: "1" });
  await enqueue({ op: "play", guild: "1" });
  assert.deepEqual(errors, ["boom"]);
  assert.deepEqual(ran, ["play"]);
});
