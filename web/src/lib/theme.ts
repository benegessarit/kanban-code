/** Theme preference — what the user picked. "system" means follow the OS. */
export type ThemePref = "system" | "light" | "dark";

/** Resolved theme — what actually renders. Always one of light/dark. */
export type Theme = "light" | "dark";

const STORAGE_KEY = "kanban-share-theme";

export function loadThemePref(): ThemePref {
  try {
    const v = localStorage.getItem(STORAGE_KEY);
    if (v === "light" || v === "dark" || v === "system") return v;
  } catch { /* SSR / privacy mode */ }
  return "system";
}

export function saveThemePref(pref: ThemePref): void {
  try { localStorage.setItem(STORAGE_KEY, pref); } catch { /* ignore */ }
}

/** Ask the browser whether the OS is currently in dark mode. Returns false
 *  when matchMedia is unavailable (jsdom without polyfill), which is a safe
 *  default for our light-first stylesheet. */
export function systemPrefersDark(): boolean {
  if (typeof window === "undefined" || typeof window.matchMedia !== "function") return false;
  return window.matchMedia("(prefers-color-scheme: dark)").matches;
}

export function resolveTheme(pref: ThemePref): Theme {
  if (pref === "system") return systemPrefersDark() ? "dark" : "light";
  return pref;
}

/** Toggle the `dark` class on <html>. Tailwind's darkMode: ["class"] keys off
 *  this. Idempotent. */
export function applyTheme(theme: Theme): void {
  if (typeof document === "undefined") return;
  const root = document.documentElement;
  if (theme === "dark") root.classList.add("dark");
  else root.classList.remove("dark");
}

/** Cycle order for the toggle button: system → light → dark → system. */
export function nextPref(current: ThemePref): ThemePref {
  return current === "system" ? "light" : current === "light" ? "dark" : "system";
}
