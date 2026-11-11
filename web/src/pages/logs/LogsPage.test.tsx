import { act, fireEvent, screen } from "@testing-library/react";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { getBuildMemory } from "../../api/actions";
import { getLogs, listLogDays } from "../../api/logs";
import type { LogPage } from "../../api/types";
import { renderWithApp } from "../../test/render";
import { LogsPage } from "./LogsPage";

vi.mock("../../api/logs");
vi.mock("../../api/actions");
vi.mock("../../context/StatusContext", () => ({
  useStatus: () => ({ status: { started_at: "t1" }, connection: "ok", restart: vi.fn(), refresh: vi.fn() }),
}));
vi.mock("../../context/ServerContext", () => {
  const server = { id: "111", name: "Test Server", icon_url: null };
  return { useServer: () => ({ server, servers: [server], selectServer: vi.fn() }) };
});

const TODAY = "2026-11-11";
const YESTERDAY = "2026-11-10";

const FIRST_PAGE: LogPage = {
  cursor: 2,
  lines: [
    { time: "01:46:25", kind: "chat", place: "Test Server #general", text: "sylvie: !buildmemory" },
    { time: "01:46:27", kind: "system", place: "", text: "🧠 !buildmemory started" },
  ],
};
const NEXT_PAGE: LogPage = { cursor: 3, lines: [{ time: "01:49:18", kind: "system", place: "", text: "🧠 finished" }] };

const settle = () => act(() => vi.advanceTimersByTimeAsync(0));
const seconds = (count: number) => act(() => vi.advanceTimersByTimeAsync(count * 1000));

beforeEach(() => {
  vi.useFakeTimers();
  vi.mocked(listLogDays).mockResolvedValue([TODAY, YESTERDAY]);
  vi.mocked(getBuildMemory).mockResolvedValue({ running: false, last_report: null, finished_at: null });
});

afterEach(() => {
  vi.useRealTimers();
  vi.resetAllMocks();
});

it("asks only for new lines, using the cursor", async () => {
  vi.mocked(getLogs).mockResolvedValueOnce(FIRST_PAGE).mockResolvedValue(NEXT_PAGE);
  renderWithApp(<LogsPage />);
  await settle();

  expect(getLogs).toHaveBeenNthCalledWith(1, TODAY, undefined);
  expect(screen.getByText("sylvie: !buildmemory")).toBeInTheDocument();
  expect(screen.getByText("Live")).toBeInTheDocument();

  await seconds(2);

  expect(getLogs).toHaveBeenNthCalledWith(2, TODAY, 2);
  expect(screen.getByText("🧠 finished")).toBeInTheDocument();
  expect(screen.getByText("sylvie: !buildmemory")).toBeInTheDocument(); // the earlier lines stay
});

it("does not poll an old day", async () => {
  vi.mocked(getLogs).mockResolvedValue(FIRST_PAGE);
  renderWithApp(<LogsPage />);
  await settle();
  vi.mocked(getLogs).mockClear();

  fireEvent.change(screen.getByLabelText("Day"), { target: { value: YESTERDAY } });
  await settle();
  await seconds(10);

  expect(getLogs).toHaveBeenCalledTimes(1);
  expect(getLogs).toHaveBeenCalledWith(YESTERDAY, undefined);
  expect(screen.queryByText("Live")).not.toBeInTheDocument();
});

it("filters what is shown", async () => {
  vi.mocked(getLogs).mockResolvedValue(FIRST_PAGE);
  renderWithApp(<LogsPage />);
  await settle();

  fireEvent.change(screen.getByLabelText("Show"), { target: { value: "system" } });

  expect(screen.queryByText("sylvie: !buildmemory")).not.toBeInTheDocument();
  expect(screen.getByText("🧠 !buildmemory started")).toBeInTheDocument();

  fireEvent.change(screen.getByLabelText("Search the log"), { target: { value: "nothing like this" } });
  expect(screen.getByText("No line matches the filters.")).toBeInTheDocument();
});

it("says so when there are no logs at all", async () => {
  vi.mocked(listLogDays).mockResolvedValue([]);
  renderWithApp(<LogsPage />);
  await settle();

  expect(screen.getByText("There are no logs yet.")).toBeInTheDocument();
  expect(getLogs).not.toHaveBeenCalled();
});
