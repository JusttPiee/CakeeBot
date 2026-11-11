import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { listChannels, setChannelAi } from "../api/channels";
import { ApiError } from "../api/client";
import type { ChannelInfo } from "../api/types";
import { renderWithApp } from "../test/render";
import { ChannelList } from "./ChannelsPage";

vi.mock("../api/channels");

const CHANNELS: ChannelInfo[] = [
  { id: "900", name: "general", ai_on: false, readable: true },
  { id: "902", name: "commands", ai_on: true, readable: true },
  { id: "901", name: "secret", ai_on: false, readable: false },
];

beforeEach(() => {
  vi.mocked(listChannels).mockResolvedValue(CHANNELS);
});

afterEach(() => {
  vi.resetAllMocks();
});

it("turns a channel on right away and tells the server", async () => {
  let finish: () => void = () => {};
  vi.mocked(setChannelAi).mockReturnValue(new Promise<void>((resolve) => (finish = resolve))); // the bot is still busy
  renderWithApp(<ChannelList serverId="111" />);
  const toggle = await screen.findByRole("switch", { name: "AI in general" });

  await userEvent.click(toggle);

  expect(toggle).toBeChecked(); // before the bot has answered
  expect(toggle).toBeDisabled(); // and it can't be clicked twice meanwhile
  expect(setChannelAi).toHaveBeenCalledWith("111", "900", true);

  finish();
  await waitFor(() => expect(toggle).toBeEnabled());
});

it("puts the switch back when the server refuses", async () => {
  vi.mocked(setChannelAi).mockRejectedValue(new ApiError(500, "Something went wrong in the bot."));
  renderWithApp(<ChannelList serverId="111" />);
  const toggle = await screen.findByRole("switch", { name: "AI in general" });

  await userEvent.click(toggle);

  await waitFor(() => expect(toggle).not.toBeChecked());
  expect(screen.getByText(/Something went wrong in the bot\./)).toBeInTheDocument();
});

it("locks channels Cake can't read", async () => {
  renderWithApp(<ChannelList serverId="111" />);

  expect(await screen.findByRole("switch", { name: "AI in secret" })).toBeDisabled();
  expect(screen.getByText("Cake can't read this channel")).toBeInTheDocument();
});

it("counts the channels with AI on", async () => {
  renderWithApp(<ChannelList serverId="111" />);

  expect(await screen.findByText("Channels with AI on: 1")).toBeInTheDocument();
});

it("filters channels by name", async () => {
  renderWithApp(<ChannelList serverId="111" />);
  await screen.findByText("general");

  await userEvent.type(screen.getByLabelText("Search channels"), "COMM");

  expect(screen.getByText("commands")).toBeInTheDocument();
  expect(screen.queryByText("general")).not.toBeInTheDocument();
});
