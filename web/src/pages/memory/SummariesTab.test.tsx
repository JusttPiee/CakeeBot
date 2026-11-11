import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, expect, it, vi } from "vitest";
import { deleteSummary, listSummaries } from "../../api/memory";
import type { ChannelSummary } from "../../api/types";
import { renderWithApp } from "../../test/render";
import { SummariesTab } from "./SummariesTab";

vi.mock("../../api/memory");

const GENERAL: ChannelSummary = {
  channel_id: "900",
  channel_name: "general",
  updated: "2026-11-04 14:02",
  text: "They planned a Valorant night.",
};
const GONE: ChannelSummary = { channel_id: "777", channel_name: "", updated: "2026-11-05 09:00", text: "Old talk." };

afterEach(() => {
  vi.resetAllMocks();
});

it("is read-only and deletes after confirming", async () => {
  vi.mocked(listSummaries).mockResolvedValue([GENERAL]);
  vi.mocked(deleteSummary).mockResolvedValue(undefined);
  renderWithApp(<SummariesTab serverId="111" />);

  await userEvent.click(await screen.findByText("# general"));

  expect(screen.getByText("They planned a Valorant night.")).toBeInTheDocument();
  expect(screen.queryByRole("textbox")).not.toBeInTheDocument();
  expect(screen.getByText(/can't be edited here/)).toBeInTheDocument();

  await userEvent.click(screen.getByRole("button", { name: "Delete summary" }));
  await userEvent.click(screen.getByRole("button", { name: "Yes, delete" }));

  expect(deleteSummary).toHaveBeenCalledWith("111", "900");
  await waitFor(() => expect(listSummaries).toHaveBeenCalledTimes(2)); // the list is loaded again
});

it("falls back to the channel id when the channel is gone", async () => {
  vi.mocked(listSummaries).mockResolvedValue([GONE]);
  renderWithApp(<SummariesTab serverId="111" />);

  expect(await screen.findByText("Channel 777")).toBeInTheDocument();
});
