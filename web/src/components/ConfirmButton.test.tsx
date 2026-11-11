import { act, render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, expect, it, vi } from "vitest";
import { LanguageProvider } from "../i18n/LanguageContext";
import { ConfirmButton } from "./ConfirmButton";

function renderButton(onConfirm: () => void) {
  render(
    <LanguageProvider>
      <ConfirmButton label="Delete note" confirmLabel="Yes, delete" onConfirm={onConfirm} danger />
    </LanguageProvider>,
  );
}

afterEach(() => {
  vi.useRealTimers();
});

it("needs a second click before it acts", async () => {
  const onConfirm = vi.fn();
  renderButton(onConfirm);

  await userEvent.click(screen.getByRole("button", { name: "Delete note" }));

  expect(onConfirm).not.toHaveBeenCalled();
  await userEvent.click(screen.getByRole("button", { name: "Yes, delete" }));
  expect(onConfirm).toHaveBeenCalledTimes(1);
  expect(screen.getByRole("button", { name: "Delete note" })).toBeInTheDocument(); // back to the start
});

it("cancels", async () => {
  const onConfirm = vi.fn();
  renderButton(onConfirm);

  await userEvent.click(screen.getByRole("button", { name: "Delete note" }));
  await userEvent.click(screen.getByRole("button", { name: "Cancel" }));

  expect(screen.getByRole("button", { name: "Delete note" })).toBeInTheDocument();
  expect(onConfirm).not.toHaveBeenCalled();
});

it("goes back by itself after a few seconds", () => {
  vi.useFakeTimers();
  renderButton(vi.fn());

  act(() => screen.getByRole("button", { name: "Delete note" }).click());
  expect(screen.getByRole("button", { name: "Yes, delete" })).toBeInTheDocument();

  act(() => {
    vi.advanceTimersByTime(4100);
  });
  expect(screen.getByRole("button", { name: "Delete note" })).toBeInTheDocument();
});
