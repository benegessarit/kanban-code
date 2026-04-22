import { useEffect, useState } from "react";
import { applyTheme, loadThemePref, resolveTheme, saveThemePref, type ThemePref, type Theme } from "./theme";

export interface UseThemeResult {
  pref: ThemePref;
  effective: Theme;
  setPref: (next: ThemePref) => void;
}

/** Central theme state. Listens to the OS color-scheme only while the user
 *  pref is "system" — switching to explicit light/dark detaches that listener
 *  so OS flips don't silently override an explicit choice. */
export function useTheme(): UseThemeResult {
  const [pref, setPrefState] = useState<ThemePref>(() => loadThemePref());
  const [effective, setEffective] = useState<Theme>(() => resolveTheme(loadThemePref()));

  useEffect(() => {
    const next = resolveTheme(pref);
    setEffective(next);
    applyTheme(next);
    saveThemePref(pref);

    if (pref !== "system") return;
    if (typeof window === "undefined" || typeof window.matchMedia !== "function") return;
    const mql = window.matchMedia("(prefers-color-scheme: dark)");
    const onChange = (): void => {
      const resolved: Theme = mql.matches ? "dark" : "light";
      setEffective(resolved);
      applyTheme(resolved);
    };
    mql.addEventListener("change", onChange);
    return () => mql.removeEventListener("change", onChange);
  }, [pref]);

  return { pref, effective, setPref: setPrefState };
}
