import { screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { getUser, listUsers } from "../../api/memory";
import type { UserNote, UserSummary } from "../../api/types";
import { renderWithApp } from "../../test/render";
import { PeopleTab } from "./PeopleTab";

vi.mock("../../api/memory");

const PEOPLE: UserSummary[] = [
  { id: "467534806927015968", name: "Anon Tokyo", description: "Valorant player", fact_count: 0, personality_off: false },
  { id: "855993053353082892", name: "fumion", description: "Minecraft modding", fact_count: 2, personality_off: false },
  { id: "694768860116811786", name: "", description: "", fact_count: 0, personality_off: true },
];

const noteOf = (person: UserSummary): UserNote => ({
  id: person.id,
  name: person.name,
  description: person.description,
  personality: `Notes about ${person.name}`,
  personality_off: person.personality_off,
  facts: [],
});

beforeEach(() => {
  vi.mocked(listUsers).mockResolvedValue(PEOPLE);
  vi.mocked(getUser).mockImplementation(async (_serverId, userId) => noteOf(PEOPLE.find((p) => p.id === userId)!));
});

afterEach(() => {
  vi.resetAllMocks();
});

it("lists the people of the server with a count", async () => {
  renderWithApp(<PeopleTab serverId="111" />);

  expect(await screen.findByText("Anon Tokyo")).toBeInTheDocument();
  expect(screen.getByText("3 people")).toBeInTheDocument();
  expect(listUsers).toHaveBeenCalledWith("111");
});

it("filters by name or id", async () => {
  renderWithApp(<PeopleTab serverId="111" />);
  await screen.findByText("Anon Tokyo");
  const search = screen.getByLabelText("Search by name or ID");

  await userEvent.type(search, "FUM");
  expect(screen.getByText("fumion")).toBeInTheDocument();
  expect(screen.queryByText("Anon Tokyo")).not.toBeInTheDocument();

  await userEvent.clear(search);
  await userEvent.type(search, "4675");
  expect(screen.getByText("Anon Tokyo")).toBeInTheDocument();
  expect(screen.queryByText("fumion")).not.toBeInTheDocument();

  await userEvent.clear(search);
  await userEvent.type(search, "nobody at all");
  expect(screen.getByText("Nobody matches that search.")).toBeInTheDocument();
});

it("labels people who opted out", async () => {
  renderWithApp(<PeopleTab serverId="111" />);

  expect(await screen.findByText("No name")).toBeInTheDocument();
  expect(screen.getByText("opted out")).toBeInTheDocument();
});

it("opens a person's note when their row is clicked", async () => {
  renderWithApp(<PeopleTab serverId="111" />);

  await userEvent.click(await screen.findByText("fumion"));

  expect(await screen.findByDisplayValue("Notes about fumion")).toBeInTheDocument();
  expect(getUser).toHaveBeenCalledWith("111", "855993053353082892");
});

it("asks before throwing away unsaved changes", async () => {
  renderWithApp(<PeopleTab serverId="111" />);
  await userEvent.click(await screen.findByText("fumion"));
  await userEvent.type(await screen.findByLabelText("Description"), " and more");

  await userEvent.click(screen.getByText("Anon Tokyo"));

  expect(screen.getByText("You have unsaved changes.")).toBeInTheDocument();
  expect(screen.getByLabelText("Description")).toHaveValue("Minecraft modding and more"); // still fumion's form

  await userEvent.click(screen.getByRole("button", { name: "Discard them" }));

  expect(await screen.findByDisplayValue("Notes about Anon Tokyo")).toBeInTheDocument();
});
