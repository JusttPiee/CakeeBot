import { screen } from "@testing-library/react";
import { afterEach, expect, it, vi } from "vitest";
import { listRecent } from "../../api/memory";
import type { RecentEntry } from "../../api/types";
import { renderWithApp } from "../../test/render";
import { RecentTab } from "./RecentTab";

vi.mock("../../api/memory");

const ANSWERED: RecentEntry = {
  kind: "exchange",
  time: "2026-11-11T12:21:00+11:00",
  channel_id: "900",
  channel_name: "test-2",
  public: true,
  speaker_id: "5",
  speaker_name: "Piee",
  text: "explain Natlan",
  answer: "Natlan is a land of fire",
};
const TAGGED: RecentEntry = {
  ...ANSWERED,
  kind: "tagged",
  channel_name: "admin-only",
  public: false,
  speaker_name: "Citlali [bot]",
  text: "hey Cake, what's up?",
  answer: null,
};

afterEach(() => {
  vi.resetAllMocks();
});

it("shows answered and unanswered lines", async () => {
  vi.mocked(listRecent).mockResolvedValue([TAGGED, ANSWERED]);
  renderWithApp(<RecentTab serverId="111" />);

  expect(await screen.findByText("explain Natlan")).toBeInTheDocument();
  expect(screen.getByText("Natlan is a land of fire")).toBeInTheDocument();
  expect(screen.getByText("hey Cake, what's up?")).toBeInTheDocument();
  expect(screen.getByText("Cake did not answer")).toBeInTheDocument();
  expect(listRecent).toHaveBeenCalledWith("111");
});

it("marks private channels", async () => {
  vi.mocked(listRecent).mockResolvedValue([TAGGED]);
  renderWithApp(<RecentTab serverId="111" />);

  expect(await screen.findByText("private")).toBeInTheDocument();
  expect(screen.getByText("# admin-only")).toBeInTheDocument();
});

it("says the log is empty after a restart", async () => {
  vi.mocked(listRecent).mockResolvedValue([]);
  renderWithApp(<RecentTab serverId="111" />);

  expect(await screen.findByText(/Nothing yet/)).toBeInTheDocument();
});
