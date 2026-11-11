import { screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, expect, it, vi } from "vitest";
import { changeItem, listGeneral } from "../../api/memory";
import type { GeneralNote } from "../../api/types";
import { renderWithApp } from "../../test/render";
import { GeneralTab } from "./GeneralTab";

vi.mock("../../api/memory");

const NOTE: GeneralNote = {
  id: "aaaaaaaa",
  date: "2026-11-07",
  author_id: "5",
  author_name: "Bach",
  subject_id: "6",
  subject_name: "Pie",
  text: "is bad at Valorant",
};
const OTHER: GeneralNote = { ...NOTE, id: "bbbbbbbb", author_name: "Pie", subject_name: "Bach", text: "owes me a drink" };

afterEach(() => {
  vi.resetAllMocks();
});

it("shows who said what about whom", async () => {
  vi.mocked(listGeneral).mockResolvedValue([NOTE, OTHER]);
  renderWithApp(<GeneralTab serverId="111" />);

  await userEvent.click(await screen.findByText("Bach → Pie"));

  expect(screen.getByDisplayValue("is bad at Valorant")).toBeInTheDocument();
  expect(screen.getByText("Bach (5)")).toBeInTheDocument();
  expect(screen.getByText("Pie (6)")).toBeInTheDocument();
  expect(screen.getByText("2026-11-07")).toBeInTheDocument();
});

it("keeps the edited note selected after its id changes", async () => {
  // The id is made from the text, so the bot gives the changed note a new id.
  const changed: GeneralNote = { ...NOTE, id: "cccccccc", date: "2026-11-11", text: "is great at Valorant" };
  vi.mocked(listGeneral).mockResolvedValueOnce([NOTE, OTHER]).mockResolvedValue([changed, OTHER]);
  vi.mocked(changeItem).mockResolvedValue(undefined);
  renderWithApp(<GeneralTab serverId="111" />);
  await userEvent.click(await screen.findByText("Bach → Pie"));

  const box = screen.getByLabelText("What they said");
  await userEvent.clear(box);
  await userEvent.type(box, "is great at Valorant");
  await userEvent.click(screen.getByRole("button", { name: "Save" }));

  expect(changeItem).toHaveBeenCalledWith("111", "aaaaaaaa", "is great at Valorant");
  expect(await screen.findByText("2026-11-11")).toBeInTheDocument(); // the detail shows the new version
  expect(screen.getByLabelText("What they said")).toHaveValue("is great at Valorant");
});

it("says so when there are no general notes", async () => {
  vi.mocked(listGeneral).mockResolvedValue([]);
  renderWithApp(<GeneralTab serverId="111" />);

  expect(await screen.findByText(/Nobody has asked Cake to remember something about someone else/)).toBeInTheDocument();
});
