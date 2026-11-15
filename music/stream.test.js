import { test } from "node:test";
import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import { PassThrough } from "node:stream";
import { ytdlpArgs, treeKillCommand, stopProgram } from "./stream.js";

// A pretend child process: still running, with an output pipe, remembers kill().
function fakeChild({ pid = 42, exitCode = null } = {}) {
  const child = new EventEmitter();
  child.pid = pid;
  child.exitCode = exitCode;
  child.signalCode = null;
  child.stdout = new PassThrough();
  child.killed = false;
  child.kill = () => { child.killed = true; };
  return child;
}

// A pretend spawn: remembers what it was asked to start.
function fakeSpawn(calls) {
  return (command, args, options) => {
    calls.push({ command, args, options });
    const killer = new EventEmitter();
    return killer;
  };
}

test("the url comes after -- so a url starting with a dash is not read as an option", () => {
  const args = ytdlpArgs("-x");
  assert.deepEqual(args.slice(-2), ["--", "-x"]);
  assert.ok(args.includes("--no-playlist"));
});

test("on Windows the whole process tree is killed with taskkill", () => {
  assert.deepEqual(treeKillCommand(1234, "win32"), ["taskkill", ["/pid", "1234", "/T", "/F"]]);
  assert.equal(treeKillCommand(1234, "linux"), null);
});

test("stopping a program closes its output pipe and kills it", () => {
  const child = fakeChild();
  stopProgram(child, "linux", fakeSpawn([]));
  assert.ok(child.stdout.destroyed);
  assert.ok(child.killed);
});

test("on Windows stopping uses taskkill without a shell", () => {
  const calls = [];
  const child = fakeChild({ pid: 77 });
  stopProgram(child, "win32", fakeSpawn(calls));
  assert.equal(calls.length, 1);
  assert.equal(calls[0].command, "taskkill");
  assert.deepEqual(calls[0].args, ["/pid", "77", "/T", "/F"]);
  assert.notEqual(calls[0].options?.shell, true);
  assert.ok(child.stdout.destroyed);
});

test("a program that already ended is not killed again", () => {
  const calls = [];
  const child = fakeChild({ exitCode: 0 });
  stopProgram(child, "win32", fakeSpawn(calls));
  assert.equal(calls.length, 0);
  assert.equal(child.killed, false);
});

test("a taskkill that cannot start does not throw", () => {
  const child = fakeChild();
  const failingSpawn = () => {
    const killer = new EventEmitter();
    process.nextTick(() => killer.emit("error", new Error("no taskkill")));
    return killer;
  };
  assert.doesNotThrow(() => stopProgram(child, "win32", failingSpawn));
});
