import { act, screen } from "@testing-library/react";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { getBuildMemory, startBuildMemory } from "../../api/actions";
import { ApiError } from "../../api/client";
import type { BuildMemoryState } from "../../api/types";
import { renderWithApp } from "../../test/render";
import { BuildMemoryButton } from "./BuildMemoryButton";

vi.mock("../../api/actions");

const IDLE: BuildMemoryState = { running: false, last_report: null, finished_at: null };
const RUNNING: BuildMemoryState = { running: true, last_report: null, finished_at: null };
const DONE: BuildMemoryState = {
  running: false,
  last_report: "✅ Read 10 messages in 1 channels and built 2 personality notes.",
  finished_at: "2026-11-11T01:49:18+11:00",
};

const settle = () => act(() => vi.advanceTimersByTimeAsync(0));
const seconds = (count: number) => act(() => vi.advanceTimersByTimeAsync(count * 1000));
const click = (name: RegExp) => act(async () => screen.getByRole("button", { name }).click());

async function renderButton() {
  renderWithApp(<BuildMemoryButton serverId="111" serverName="Test Server" />);
  await settle();
}

beforeEach(() => {
  vi.useFakeTimers();
  vi.mocked(startBuildMemory).mockResolvedValue(undefined);
});

afterEach(() => {
  vi.useRealTimers();
  vi.resetAllMocks();
});

it("warns about cost before it starts", async () => {
  vi.mocked(getBuildMemory).mockResolvedValue(IDLE);
  await renderButton();

  await click(/Run !buildmemory for Test Server/);

  expect(startBuildMemory).not.toHaveBeenCalled();
  expect(screen.getByText(/uses OpenAI tokens/)).toBeInTheDocument();

  await click(/Yes, run it/);
  expect(startBuildMemory).toHaveBeenCalledWith("111");
});

it("shows the report when the build finishes", async () => {
  vi.mocked(getBuildMemory).mockResolvedValue(RUNNING);
  await renderButton();
  expect(screen.getByText("!buildmemory is running…")).toBeInTheDocument();
  expect(screen.getByRole("button", { name: /Run !buildmemory/ })).toBeDisabled();

  vi.mocked(getBuildMemory).mockResolvedValue(DONE);
  await seconds(3);

  expect(screen.getByText(/built 2 personality notes/)).toBeInTheDocument();
  expect(screen.getByRole("button", { name: /Run !buildmemory/ })).toBeEnabled();
});

it("does not keep asking while nothing is running", async () => {
  vi.mocked(getBuildMemory).mockResolvedValue(IDLE);
  await renderButton();

  await seconds(30);

  expect(getBuildMemory).toHaveBeenCalledTimes(1);
});

it("says so when a build is already running", async () => {
  vi.mocked(getBuildMemory).mockResolvedValue(IDLE);
  vi.mocked(startBuildMemory).mockRejectedValue(new ApiError(409, "already running"));
  await renderButton();

  await click(/Run !buildmemory/);
  await click(/Yes, run it/);
  await settle();

  expect(screen.getByText("!buildmemory is already running.")).toBeInTheDocument();
});
