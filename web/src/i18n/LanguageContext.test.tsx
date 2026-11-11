import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { expect, it } from "vitest";
import { LanguageProvider, useLanguage, useT } from "./LanguageContext";

// A tiny component that shows one translated text and a button to switch language.
function Probe() {
  const t = useT();
  const { setLanguage } = useLanguage();
  return (
    <div>
      <span data-testid="text">{t("nav.memory")}</span>
      <span data-testid="count">{t("memory.people.count", { count: 17 })}</span>
      <button onClick={() => setLanguage("vi")}>switch</button>
    </div>
  );
}

it("starts in English, switches to Vietnamese, and remembers it", async () => {
  render(
    <LanguageProvider>
      <Probe />
    </LanguageProvider>,
  );
  expect(screen.getByTestId("text")).toHaveTextContent("Memory");

  await userEvent.click(screen.getByText("switch"));

  expect(screen.getByTestId("text")).toHaveTextContent("Bộ nhớ");
  expect(localStorage.getItem("cake.lang")).toBe("vi");
});

it("starts in the language chosen last time", () => {
  localStorage.setItem("cake.lang", "vi");
  render(
    <LanguageProvider>
      <Probe />
    </LanguageProvider>,
  );
  expect(screen.getByTestId("text")).toHaveTextContent("Bộ nhớ");
});

it("fills in {name} variables", () => {
  render(
    <LanguageProvider>
      <Probe />
    </LanguageProvider>,
  );
  expect(screen.getByTestId("count")).toHaveTextContent("17 people");
});
