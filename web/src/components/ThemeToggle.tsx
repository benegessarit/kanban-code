import { Monitor, Moon, Sun } from "lucide-react";
import { useTheme } from "@/lib/useTheme";
import { nextPref, type ThemePref } from "@/lib/theme";
import { cn } from "@/lib/utils";

const LABELS: Record<ThemePref, string> = {
  system: "Theme: follows system",
  light: "Theme: light",
  dark: "Theme: dark",
};

/** Cycle button: System → Light → Dark → System. Icon reflects current pref
 *  (not the effective theme) so the user can see what mode they picked. */
export function ThemeToggle({ className }: { className?: string }): React.ReactElement {
  const { pref, setPref } = useTheme();
  const Icon = pref === "system" ? Monitor : pref === "light" ? Sun : Moon;

  return (
    <button
      type="button"
      onClick={() => setPref(nextPref(pref))}
      aria-label={LABELS[pref]}
      title={LABELS[pref]}
      className={cn(
        "inline-flex items-center justify-center h-8 w-8 rounded-md",
        "text-muted-foreground hover:text-foreground hover:bg-accent",
        "transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring",
        className,
      )}
    >
      <Icon className="h-4 w-4" />
    </button>
  );
}
