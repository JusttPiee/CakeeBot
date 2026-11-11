import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, expect, it, vi } from "vitest";
import { ApiError } from "../../api/client";
import { addFact, changeItem, removeItem } from "../../api/memory";
import type { Fact } from "../../api/types";
import { renderWithApp } from "../../test/render";
import { FactList } from "./FactList";

vi.mock("../../api/memory");

const FACTS: Fact[] = [{ id: "a1b2c3d4", date: "2026-11-04", text: "no anime" }];

function renderList(facts: Fact[] = FACTS) {
  const onChanged = vi.fn();
  renderWithApp(<FactList serverId="111" userId="5" facts={facts} onChanged={onChanged} />);
  return { onChanged };
}

afterEach(() => {
  vi.resetAllMocks();
});

it("adds a fact and reloads", async () => {
  vi.mocked(addFact).mockResolvedValue(undefined);
  const { onChanged } = renderList();

  await userEvent.type(screen.getByLabelText("New fact"), "mains Jett{Enter}");

  expect(addFact).toHaveBeenCalledWith("111", "5", "mains Jett");
  await waitFor(() => expect(onChanged).toHaveBeenCalled());
  expect(screen.getByLabelText("New fact")).toHaveValue(""); // ready for the next one
});

it("edits a fact in place", async () => {
  vi.mocked(changeItem).mockResolvedValue(undefined);
  const { onChanged } = renderList();

  await userEvent.click(screen.getByRole("button", { name: "Edit: no anime" }));
  const box = screen.getByDisplayValue("no anime");
  await userEvent.clear(box);
  await userEvent.type(box, "likes anime now{Enter}");

  expect(changeItem).toHaveBeenCalledWith("111", "a1b2c3d4", "likes anime now");
  await waitFor(() => expect(onChanged).toHaveBeenCalled());
});

it("cancels an edit with Escape", async () => {
  renderList();

  await userEvent.click(screen.getByRole("button", { name: "Edit: no anime" }));
  await userEvent.type(screen.getByDisplayValue("no anime"), " at all{Escape}");

  expect(changeItem).not.toHaveBeenCalled();
  expect(screen.getByText("no anime")).toBeInTheDocument();
});

it("removes a fact after confirming", async () => {
  vi.mocked(removeItem).mockResolvedValue(undefined);
  const { onChanged } = renderList();

  await userEvent.click(screen.getByRole("button", { name: "Delete: no anime" }));
  expect(removeItem).not.toHaveBeenCalled();
  await userEvent.click(screen.getByRole("button", { name: "Delete?" }));

  expect(removeItem).toHaveBeenCalledWith("111", "a1b2c3d4");
  await waitFor(() => expect(onChanged).toHaveBeenCalled());
});

it("shows the server's message when a fact is refused", async () => {
  vi.mocked(addFact).mockRejectedValue(new ApiError(422, "The text can be at most 500 characters."));
  const { onChanged } = renderList();

  await userEvent.type(screen.getByLabelText("New fact"), "way too long{Enter}");

  expect(await screen.findByText("The text can be at most 500 characters.")).toBeInTheDocument();
  expect(screen.getByLabelText("New fact")).toHaveValue("way too long"); // nothing typed is lost
  expect(onChanged).not.toHaveBeenCalled();
});

it("says so when there is nothing yet", () => {
  renderList([]);
  expect(screen.getByText("Nothing yet.")).toBeInTheDocument();
});
