// Runs before every test file.
import "@testing-library/jest-dom/vitest"; // adds checks like expect(button).toBeDisabled()
import { cleanup } from "@testing-library/react";
import { afterEach } from "vitest";

// A tiny stand-in for the browser's localStorage. Newer Node versions ship their own half-working
// `localStorage`, which hides the pretend browser's one, so tests get this predictable copy instead.
class MemoryStorage {
  private items = new Map<string, string>();

  getItem(key: string): string | null {
    return this.items.get(key) ?? null;
  }

  setItem(key: string, value: string): void {
    this.items.set(key, String(value));
  }

  removeItem(key: string): void {
    this.items.delete(key);
  }

  clear(): void {
    this.items.clear();
  }
}

// Set directly (not with vi.stubGlobal), so a test that calls vi.unstubAllGlobals() keeps it.
Object.defineProperty(globalThis, "localStorage", { value: new MemoryStorage(), configurable: true, writable: true });

// Each test starts with an empty page and empty browser storage.
afterEach(() => {
  cleanup();
  localStorage.clear();
});

// The pretend browser has no matchMedia. The Motion library asks it whether the user wants less
// motion; this answers "no preference" for every question.
window.matchMedia ??= ((query: string) => ({
  matches: false,
  media: query,
  onchange: null,
  addEventListener: () => {},
  removeEventListener: () => {},
  addListener: () => {},
  removeListener: () => {},
  dispatchEvent: () => false,
})) as unknown as typeof window.matchMedia;
