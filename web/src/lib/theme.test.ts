import { describe, test, expect, beforeEach, afterEach, vi } from "vitest";
import {
  applyTheme,
  loadThemePref,
  nextPref,
  resolveTheme,
  saveThemePref,
  systemPrefersDark,
} from "./theme";

beforeEach(() => {
  localStorage.clear();
  document.documentElement.classList.remove("dark");
});

describe("theme pref storage", () => {
  test("defaults to 'system' when nothing is saved", () => {
    expect(loadThemePref()).toBe("system");
  });

  test("persists and re-reads the user's choice", () => {
    saveThemePref("dark");
    expect(loadThemePref()).toBe("dark");
    saveThemePref("light");
    expect(loadThemePref()).toBe("light");
  });

  test("falls back to 'system' when localStorage holds garbage", () => {
    localStorage.setItem("kanban-share-theme", "mauve");
    expect(loadThemePref()).toBe("system");
  });
});

describe("applyTheme", () => {
  test("adds the 'dark' class when dark", () => {
    applyTheme("dark");
    expect(document.documentElement.classList.contains("dark")).toBe(true);
  });

  test("removes the 'dark' class when light", () => {
    document.documentElement.classList.add("dark");
    applyTheme("light");
    expect(document.documentElement.classList.contains("dark")).toBe(false);
  });

  test("is idempotent", () => {
    applyTheme("dark");
    applyTheme("dark");
    expect(document.documentElement.classList.contains("dark")).toBe(true);
  });
});

describe("resolveTheme + system detection", () => {
  const origMatchMedia = window.matchMedia;
  afterEach(() => { window.matchMedia = origMatchMedia; });

  function stubMatchMedia(matches: boolean): void {
    window.matchMedia = vi.fn().mockImplementation((q: string) => ({
      matches, media: q,
      onchange: null,
      addListener: () => {}, removeListener: () => {},
      addEventListener: () => {}, removeEventListener: () => {},
      dispatchEvent: () => false,
    })) as unknown as typeof window.matchMedia;
  }

  test("system pref follows the OS (dark)", () => {
    stubMatchMedia(true);
    expect(systemPrefersDark()).toBe(true);
    expect(resolveTheme("system")).toBe("dark");
  });

  test("system pref follows the OS (light)", () => {
    stubMatchMedia(false);
    expect(resolveTheme("system")).toBe("light");
  });

  test("explicit pref wins over the OS", () => {
    stubMatchMedia(true);
    expect(resolveTheme("light")).toBe("light");
    stubMatchMedia(false);
    expect(resolveTheme("dark")).toBe("dark");
  });
});

describe("nextPref cycle", () => {
  test("system → light → dark → system", () => {
    expect(nextPref("system")).toBe("light");
    expect(nextPref("light")).toBe("dark");
    expect(nextPref("dark")).toBe("system");
  });
});
