import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, expect, it, vi } from "vitest";
import { ApiError } from "../../api/client";
import { deleteEvent, saveEvent } from "../../api/memory";
import type { EventNote } from "../../api/types";
import { renderWithApp } from "../../test/render";
import { EventForm } from "./EventForm";

vi.mock("../../api/memory");

const EVENT: EventNote = {
  slug: "valorant-cup",
  title: "Valorant Cup",
  when: "2099-11-21 20:00",
  details: "bring snacks",
  past: false,
};

function renderForm() {
  const onSaved = vi.fn();
  const onDeleted = vi.fn();
  renderWithApp(<EventForm serverId="111" event={EVENT} onSaved={onSaved} onDeleted={onDeleted} />);
  return { onSaved, onDeleted };
}

async function retype(label: string, text: string) {
  const box = screen.getByLabelText(label);
  await userEvent.clear(box);
  await userEvent.type(box, text);
}

afterEach(() => {
  vi.resetAllMocks();
});

it("blocks saving while the date is not in the right format", async () => {
  renderForm();

  await retype("When", "next friday");
  expect(screen.getByText("Write it like 2026-11-21 or 2026-11-21 20:00.")).toHaveClass("error-text");
  expect(screen.getByRole("button", { name: "Save" })).toBeDisabled();

  await retype("When", "2099-11-22");
  expect(screen.getByRole("button", { name: "Save" })).toBeEnabled();
});

it("blocks saving an empty title", async () => {
  renderForm();
  await userEvent.clear(screen.getByLabelText("Title"));
  expect(screen.getByRole("button", { name: "Save" })).toBeDisabled();
});

it("shows the server's message for an impossible date", async () => {
  vi.mocked(saveEvent).mockRejectedValue(new ApiError(422, "The time must look like YYYY-MM-DD, and be a real date."));
  renderForm();

  await retype("When", "2099-02-30");
  await userEvent.click(screen.getByRole("button", { name: "Save" }));

  expect(await screen.findByText(/be a real date/)).toBeInTheDocument();
});

it("follows the event to its new slug after a rename", async () => {
  vi.mocked(saveEvent).mockResolvedValue({ ...EVENT, slug: "valo-night", title: "Valo Night" });
  const { onSaved } = renderForm();

  await retype("Title", "Valo Night");
  await userEvent.click(screen.getByRole("button", { name: "Save" }));

  expect(saveEvent).toHaveBeenCalledWith("111", "valorant-cup", {
    title: "Valo Night",
    when: "2099-11-21 20:00",
    details: "bring snacks",
  });
  await waitFor(() => expect(onSaved).toHaveBeenCalledWith("valo-night"));
});

it("deletes after confirming", async () => {
  vi.mocked(deleteEvent).mockResolvedValue(undefined);
  const { onDeleted } = renderForm();

  await userEvent.click(screen.getByRole("button", { name: "Delete event" }));
  await userEvent.click(screen.getByRole("button", { name: "Yes, delete" }));

  expect(deleteEvent).toHaveBeenCalledWith("111", "valorant-cup");
  await waitFor(() => expect(onDeleted).toHaveBeenCalled());
});
