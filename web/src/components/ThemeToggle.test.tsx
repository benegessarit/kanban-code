import { describe, test, expect, beforeEach, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { ThemeToggle } from "./ThemeToggle";

beforeEach(() => {
  localStorage.clear();
  document.documentElement.classList.remove("dark");
  // Pin matchMedia to "light OS" so "system" resolves deterministically.
  window.matchMedia = vi.fn().mockImplementation((q: string) => ({
    matches: false, media: q,
    onchange: null,
    addListener: () => {}, removeListener: () => {},
    addEventListener: () => {}, removeEventListener: () => {},
    dispatchEvent: () => false,
  })) as unknown as typeof window.matchMedia;
});

describe("ThemeToggle", () => {
  test("defaults to 'system' (shows the monitor icon)", () => {
    render(<ThemeToggle />);
    expect(screen.getByRole("button", { name: /follows system/i })).toBeInTheDocument();
  });

  test("cycles system → light → dark → system and updates the <html> class", async () => {
    const user = userEvent.setup();
    render(<ThemeToggle />);
    const btn = screen.getByRole("button");

    // Starts: system → effective light (mocked OS = light).
    expect(document.documentElement.classList.contains("dark")).toBe(false);

    await user.click(btn);
    expect(screen.getByRole("button", { name: /theme: light/i })).toBeInTheDocument();
    expect(document.documentElement.classList.contains("dark")).toBe(false);

    await user.click(btn);
    expect(screen.getByRole("button", { name: /theme: dark/i })).toBeInTheDocument();
    expect(document.documentElement.classList.contains("dark")).toBe(true);

    await user.click(btn);
    expect(screen.getByRole("button", { name: /follows system/i })).toBeInTheDocument();
    // OS is mocked as light, so back to light.
    expect(document.documentElement.classList.contains("dark")).toBe(false);
  });

  test("persists the chosen pref across remounts", async () => {
    const user = userEvent.setup();
    const { unmount } = render(<ThemeToggle />);
    await user.click(screen.getByRole("button")); // light
    await user.click(screen.getByRole("button")); // dark
    unmount();

    render(<ThemeToggle />);
    expect(screen.getByRole("button", { name: /theme: dark/i })).toBeInTheDocument();
    expect(document.documentElement.classList.contains("dark")).toBe(true);
  });
});
