import { act, render, screen } from "@testing-library/react";
import { afterEach, expect, it, vi } from "vitest";
import { ApiError } from "./api/client";
import { getStatus } from "./api/status";
import type { Status } from "./api/types";
import { App } from "./App";

vi.mock("./api/status");
// The pages load their own data; these tests are only about the frame around them.
vi.mock("./pages/memory/MemoryPage", () => ({ MemoryPage: () => <div>memory page</div> }));

const STATUS: Status = {
  bot_name: "Cake",
  started_at: "t1",
  restart_needed: false,
  servers: [{ id: "111", name: "Test Server", icon_url: null }],
};

afterEach(() => {
  vi.useRealTimers();
  vi.resetAllMocks();
});

it("shows the token page instead of the app when the token is missing", async () => {
  vi.mocked(getStatus).mockRejectedValue(new ApiError(401, "Missing or wrong token."));

  render(<App />);

  expect(await screen.findByText(/This browser needs the link from Cake's terminal/)).toBeInTheDocument();
  expect(screen.queryByRole("navigation")).not.toBeInTheDocument();
});

it("shows the sidebar with the bot's servers and the four pages", async () => {
  vi.mocked(getStatus).mockResolvedValue(STATUS);

  render(<App />);

  expect(await screen.findByRole("link", { name: /Memory/ })).toBeInTheDocument();
  expect(screen.getByRole("link", { name: /AI channels/ })).toBeInTheDocument();
  expect(screen.getByRole("link", { name: /Config/ })).toBeInTheDocument();
  expect(screen.getByRole("link", { name: /Logs/ })).toBeInTheDocument();
  expect(screen.getByRole("combobox", { name: "Server" })).toHaveValue("111");
  expect(await screen.findByText("memory page")).toBeInTheDocument(); // "/" goes to the Memory page
});

it("keeps the page visible under a banner while reconnecting", async () => {
  vi.useFakeTimers();
  vi.mocked(getStatus).mockResolvedValue(STATUS);
  render(<App />);
  await act(() => vi.advanceTimersByTimeAsync(0));
  expect(screen.getByText("memory page")).toBeInTheDocument();

  vi.mocked(getStatus).mockRejectedValue(new ApiError(0, "Can't reach the bot."));
  await act(() => vi.advanceTimersByTimeAsync(5000));

  expect(screen.getByRole("status")).toHaveTextContent("Can't reach Cake. Trying again…");
  expect(screen.getByText("memory page")).toBeInTheDocument(); // not a blank page
});
