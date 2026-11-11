import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, expect, it, vi } from "vitest";
import { deleteUser, saveUser } from "../../api/memory";
import type { UserNote } from "../../api/types";
import { renderWithApp } from "../../test/render";
import { UserNoteForm } from "./UserNoteForm";

vi.mock("../../api/memory");

const NOTE: UserNote = {
  id: "5",
  name: "Bach",
  description: "likes Valorant",
  personality: "Plays most nights",
  personality_off: false,
  facts: [],
};

function renderForm(note: UserNote = NOTE) {
  const onSaved = vi.fn();
  const onDeleted = vi.fn();
  renderWithApp(<UserNoteForm serverId="111" note={note} onSaved={onSaved} onDeleted={onDeleted} />);
  return { onSaved, onDeleted };
}

afterEach(() => {
  vi.resetAllMocks();
});

it("saves only description, personality and the switch", async () => {
  vi.mocked(saveUser).mockResolvedValue({ ...NOTE, description: "new" });
  const { onSaved } = renderForm();

  const description = screen.getByLabelText("Description");
  await userEvent.clear(description);
  await userEvent.type(description, "new");
  await userEvent.click(screen.getByRole("button", { name: "Save" }));

  expect(saveUser).toHaveBeenCalledWith("111", "5", {
    description: "new",
    personality: "Plays most nights",
    personality_off: false,
  });
  await waitFor(() => expect(onSaved).toHaveBeenCalledWith({ ...NOTE, description: "new" }));
});

it("keeps Save disabled until something changes", async () => {
  renderForm();
  const save = screen.getByRole("button", { name: "Save" });
  expect(save).toBeDisabled();

  await userEvent.type(screen.getByLabelText("Personality"), "!");

  expect(save).toBeEnabled();
});

it("locks the text fields and warns when personality is turned off", async () => {
  renderForm();

  await userEvent.click(screen.getByRole("switch", { name: "Personality notes off" }));

  expect(screen.getByLabelText("Description")).toBeDisabled();
  expect(screen.getByLabelText("Personality")).toBeDisabled();
  expect(screen.getByText("Saving will erase the personality text and description.")).toBeInTheDocument();
});

it("shows the bot's message when saving fails, and keeps what was typed", async () => {
  const { ApiError } = await vi.importActual<typeof import("../../api/client")>("../../api/client");
  vi.mocked(saveUser).mockRejectedValue(new ApiError(500, "Something went wrong in the bot."));
  renderForm();

  await userEvent.type(screen.getByLabelText("Description"), " a lot");
  await userEvent.click(screen.getByRole("button", { name: "Save" }));

  expect(await screen.findByText(/Something went wrong in the bot\./)).toBeInTheDocument();
  expect(screen.getByLabelText("Description")).toHaveValue("likes Valorant a lot");
});

it("deletes only after confirming", async () => {
  vi.mocked(deleteUser).mockResolvedValue(undefined);
  const { onDeleted } = renderForm();

  await userEvent.click(screen.getByRole("button", { name: "Delete note" }));
  expect(deleteUser).not.toHaveBeenCalled();

  await userEvent.click(screen.getByRole("button", { name: "Yes, delete the whole note" }));

  expect(deleteUser).toHaveBeenCalledWith("111", "5");
  await waitFor(() => expect(onDeleted).toHaveBeenCalled());
});
