import { expect, it } from "vitest";
import type { LogLine } from "../../api/types";
import { filterLogLines } from "./filterLogLines";

const lines: LogLine[] = [
  { time: "01:46:25", kind: "chat", place: "Test Server #general", text: "sylvie: !buildmemory" },
  { time: "01:46:27", kind: "system", place: "", text: "🧠 !buildmemory started" },
  { time: "01:50:00", kind: "chat", place: "Other #chat", text: "bob: hello" },
];

const everything = { kind: "all", serverName: null, text: "" } as const;

it("shows everything when no filter is set", () => {
  expect(filterLogLines(lines, everything)).toEqual(lines);
});

it("filters by kind", () => {
  expect(filterLogLines(lines, { ...everything, kind: "system" })).toHaveLength(1);
  expect(filterLogLines(lines, { ...everything, kind: "chat" })).toHaveLength(2);
});

it("filters chat by server but keeps system lines", () => {
  const shown = filterLogLines(lines, { ...everything, serverName: "Test Server" });
  expect(shown.map((line) => line.time)).toEqual(["01:46:25", "01:46:27"]);
});

it("does not confuse a server with another whose name starts the same", () => {
  const similar: LogLine[] = [{ time: "02:00:00", kind: "chat", place: "Test Server 2 #general", text: "x: y" }];
  expect(filterLogLines(similar, { ...everything, serverName: "Test Server" })).toHaveLength(0);
});

it("searches place and text without caring about case", () => {
  expect(filterLogLines(lines, { ...everything, text: "BUILDMEMORY" })).toHaveLength(2);
  expect(filterLogLines(lines, { ...everything, text: "#chat" })).toHaveLength(1);
});
