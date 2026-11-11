import { act, render, screen } from "@testing-library/react";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { restartBot } from "../api/actions";
import { ApiError } from "../api/client";
import { getStatus } from "../api/status";
import type { Status } from "../api/types";
import { StatusProvider, useStatus } from "./StatusContext";

vi.mock("../api/status");
vi.mock("../api/actions");

const statusAt = (startedAt: string): Status => ({
  bot_name: "Cake",
  started_at: startedAt,
  restart_needed: false,
  servers: [],
});

// Shows what the context says, and has a button that asks for a restart.
function Probe() {
  const { connection, needsToken, status, restart } = useStatus();
  return (
    <div>
      <span data-testid="connection">{connection}</span>
      <span data-testid="token">{needsToken ? "needs token" : "has token"}</span>
      <span data-testid="started">{status?.started_at ?? "none"}</span>
      <button onClick={() => void restart()}>restart</button>
    </div>
  );
}

// Render and let the first status check finish.
async function renderProbe() {
  render(
    <StatusProvider>
      <Probe />
    </StatusProvider>,
  );
  await act(() => vi.advanceTimersByTimeAsync(0));
}

const seconds = (count: number) => act(() => vi.advanceTimersByTimeAsync(count * 1000));

beforeEach(() => {
  vi.useFakeTimers();
  vi.mocked(restartBot).mockResolvedValue(undefined);
});

afterEach(() => {
  vi.useRealTimers();
  vi.resetAllMocks();
});

it("asks for the token page on 401", async () => {
  vi.mocked(getStatus).mockRejectedValue(new ApiError(401, "Missing or wrong token."));

  await renderProbe();

  expect(screen.getByTestId("token")).toHaveTextContent("needs token");
});

it("shows reconnecting when the bot is unreachable, then recovers", async () => {
  vi.mocked(getStatus).mockResolvedValue(statusAt("t1"));
  await renderProbe();
  expect(screen.getByTestId("connection")).toHaveTextContent("ok");

  vi.mocked(getStatus).mockRejectedValue(new ApiError(0, "Can't reach the bot."));
  await seconds(5);
  expect(screen.getByTestId("connection")).toHaveTextContent("reconnecting");
  expect(screen.getByTestId("started")).toHaveTextContent("t1"); // the last known status stays

  vi.mocked(getStatus).mockResolvedValue(statusAt("t1"));
  await seconds(1);
  expect(screen.getByTestId("connection")).toHaveTextContent("ok");
});

it("waits for a new started_at after restart", async () => {
  vi.mocked(getStatus).mockResolvedValue(statusAt("t1"));
  await renderProbe();

  await act(async () => screen.getByText("restart").click());
  expect(restartBot).toHaveBeenCalledTimes(1);
  expect(screen.getByTestId("connection")).toHaveTextContent("restarting");

  await seconds(2); // the old bot is still answering
  expect(screen.getByTestId("connection")).toHaveTextContent("restarting");

  vi.mocked(getStatus).mockRejectedValue(new ApiError(0, "Can't reach the bot.")); // it went down
  await seconds(2);
  expect(screen.getByTestId("connection")).toHaveTextContent("restarting");

  vi.mocked(getStatus).mockResolvedValue(statusAt("t2")); // the new bot is up
  await seconds(1);
  expect(screen.getByTestId("connection")).toHaveTextContent("ok");
  expect(screen.getByTestId("started")).toHaveTextContent("t2");
});

it("gives up after 30 seconds, but still notices when the bot comes back", async () => {
  vi.mocked(getStatus).mockResolvedValue(statusAt("t1"));
  await renderProbe();
  await act(async () => screen.getByText("restart").click());

  vi.mocked(getStatus).mockRejectedValue(new ApiError(0, "Can't reach the bot."));
  await seconds(31);
  expect(screen.getByTestId("connection")).toHaveTextContent("stopped");

  vi.mocked(getStatus).mockResolvedValue(statusAt("t2")); // started by hand with start.bat
  await seconds(1);
  expect(screen.getByTestId("connection")).toHaveTextContent("ok");
});
