import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { ApiError } from "../../api/client";
import { getConfig, saveConfig } from "../../api/config";
import type { ConfigData } from "../../api/types";
import { renderWithApp } from "../../test/render";
import { ConfigPage } from "./ConfigPage";

vi.mock("../../api/config");

// The page asks the status context for restart(); the test gives it a pretend one it can watch.
const restart = vi.fn();
const refresh = vi.fn();
vi.mock("../../context/StatusContext", () => ({
  useStatus: () => ({ status: { started_at: "t1" }, connection: "ok", restart, refresh }),
}));

const CONFIG: ConfigData = {
  restart_needed: false,
  read_only: [
    { name: "OPENAI_MODEL", value: "gpt-6-luna" },
    { name: "OPENAI_TEMPERATURE", value: null },
  ],
  groups: [
    {
      id: "chat",
      fields: [
        {
          name: "OPENAI_REASONING_EFFORT",
          type: "choice",
          min: null,
          max: null,
          options: ["none", "low", "medium", "high", "xhigh"],
          default: "low",
          saved: null,
          running: "low",
        },
      ],
    },
    {
      id: "history",
      fields: [
        { name: "MAX_HISTORY_MESSAGES", type: "integer", min: 10, max: 200, options: null, default: 45, saved: null, running: 45 },
        { name: "MAX_TOOL_ROUNDS", type: "integer", min: 1, max: 20, options: null, default: 7, saved: 9, running: 7 },
      ],
    },
  ],
};

const HISTORY_LABEL = "Messages kept per channel";

async function typeInto(label: string, text: string) {
  const box = await screen.findByLabelText(label);
  await userEvent.clear(box);
  await userEvent.type(box, text);
}

beforeEach(() => {
  vi.mocked(getConfig).mockResolvedValue(CONFIG);
});

afterEach(() => {
  vi.resetAllMocks();
});

it("shows saved values, defaults and what is running", async () => {
  renderWithApp(<ConfigPage />);

  expect(await screen.findByLabelText(HISTORY_LABEL)).toHaveValue("45");
  expect(screen.getByLabelText("Tool rounds per reply")).toHaveValue("9"); // the saved value, not the default
  expect(screen.getByText("running: 7")).toBeInTheDocument(); // until the next restart
  expect(screen.getByLabelText("Thinking effort")).toHaveValue("low");
});

it("sends only the fields that changed", async () => {
  vi.mocked(saveConfig).mockResolvedValue({ ...CONFIG, restart_needed: true });
  renderWithApp(<ConfigPage />);

  await typeInto(HISTORY_LABEL, "60");
  await userEvent.click(screen.getByRole("button", { name: "Save" }));

  expect(saveConfig).toHaveBeenCalledWith({ MAX_HISTORY_MESSAGES: 60 });
});

it("blocks a number outside the limits", async () => {
  renderWithApp(<ConfigPage />);

  await typeInto(HISTORY_LABEL, "5");

  expect(screen.getByText("Must be a whole number from 10 to 200.")).toBeInTheDocument();
  expect(screen.getByRole("button", { name: "Save" })).toBeDisabled();

  await typeInto(HISTORY_LABEL, "60.5");
  expect(screen.getByRole("button", { name: "Save" })).toBeDisabled();
});

it("puts the server's messages on the right fields", async () => {
  vi.mocked(saveConfig).mockRejectedValue(
    new ApiError(422, "refused", { MAX_HISTORY_MESSAGES: "Must be above COMPACT_TARGET_MESSAGES (20)." }),
  );
  renderWithApp(<ConfigPage />);

  await typeInto(HISTORY_LABEL, "15");
  await userEvent.click(screen.getByRole("button", { name: "Save" }));

  expect(await screen.findByText("Must be above COMPACT_TARGET_MESSAGES (20).")).toBeInTheDocument();
  expect(screen.getByLabelText(HISTORY_LABEL)).toHaveValue("15"); // what was typed stays
});

it("shows the restart banner after saving and restarts from it", async () => {
  vi.mocked(saveConfig).mockResolvedValue({ ...CONFIG, restart_needed: true });
  renderWithApp(<ConfigPage />);

  await typeInto(HISTORY_LABEL, "60");
  await userEvent.click(screen.getByRole("button", { name: "Save" }));

  expect(await screen.findByText(/Saved. Restart Cake to apply the changes./)).toBeInTheDocument();
  expect(refresh).toHaveBeenCalled(); // so the sidebar shows its "restart needed" dot too

  await userEvent.click(screen.getByRole("button", { name: /Restart now/ }));
  expect(restart).toHaveBeenCalledTimes(1);
});

it("resets a field to its default", async () => {
  vi.mocked(saveConfig).mockResolvedValue(CONFIG);
  renderWithApp(<ConfigPage />);
  await screen.findByLabelText("Tool rounds per reply");

  await userEvent.click(screen.getByRole("button", { name: "Reset Tool rounds per reply" }));
  expect(screen.getByLabelText("Tool rounds per reply")).toHaveValue("7");

  await userEvent.click(screen.getByRole("button", { name: "Save" }));
  await waitFor(() => expect(saveConfig).toHaveBeenCalledWith({ MAX_TOOL_ROUNDS: 7 }));
});

it("shows .env settings as read-only", async () => {
  renderWithApp(<ConfigPage />);

  expect(await screen.findByText("gpt-6-luna")).toBeInTheDocument();
  expect(screen.getByText("OPENAI_MODEL")).toBeInTheDocument();
  expect(screen.queryByDisplayValue("gpt-6-luna")).not.toBeInTheDocument(); // text, not an input
});
