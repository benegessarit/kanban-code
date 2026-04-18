/**
 * Handle generation for chat participants.
 *
 * A handle is a short human-readable `@name` derived from a card's display
 * title. Handles are scoped per-channel; the same card may have different
 * handles in different channels only when a collision forces disambiguation.
 */

const MAX_HANDLE_LEN = 24;

/** Slugify into `@lower_snake_case`. No leading @. Empty string if nothing usable. */
export function slugifyDisplay(display: string): string {
  const lowered = display.toLowerCase();
  // Replace any non [a-z0-9] run with a single underscore
  const withUnderscores = lowered.replace(/[^a-z0-9]+/g, "_");
  const trimmed = withUnderscores.replace(/^_+|_+$/g, "");
  if (!trimmed) return "";
  return trimmed;
}

/** Truncate to MAX_HANDLE_LEN, prefer ending on an underscore boundary. */
export function truncateSlug(slug: string, maxLen: number = MAX_HANDLE_LEN): string {
  if (slug.length <= maxLen) return slug;
  const cut = slug.slice(0, maxLen);
  // Prefer cutting at the last underscore if within the last 8 chars.
  const lastUnderscore = cut.lastIndexOf("_");
  if (lastUnderscore >= Math.floor(maxLen * 0.6)) {
    return cut.slice(0, lastUnderscore);
  }
  return cut.replace(/_+$/, "");
}

/**
 * Disambiguate a base slug against a set of already-taken slugs (no @ prefix).
 * Returns the first non-colliding `slug`, `slug_2`, `slug_3` … that fits the max length.
 */
export function disambiguate(base: string, taken: Set<string>, maxLen: number = MAX_HANDLE_LEN): string {
  if (!taken.has(base)) return base;
  let n = 2;
  while (true) {
    const suffix = `_${n}`;
    const trimmedBase = base.slice(0, Math.max(1, maxLen - suffix.length));
    const candidate = trimmedBase + suffix;
    if (!taken.has(candidate)) return candidate;
    n += 1;
    if (n > 99) throw new Error(`Unable to disambiguate handle for base "${base}" after 99 tries`);
  }
}

/** Convenience: derive a handle from a card's display title plus a set of taken handles. */
export function deriveHandle(
  display: string,
  taken: Set<string>,
  maxLen: number = MAX_HANDLE_LEN
): string {
  const base = truncateSlug(slugifyDisplay(display), maxLen) || "agent";
  return disambiguate(base, taken, maxLen);
}

/** Format a handle string back with the leading `@`. Idempotent. */
export function formatHandle(h: string): string {
  if (h.startsWith("@")) return h;
  return "@" + h;
}

/** Strip a leading `@` if present. */
export function stripAt(h: string): string {
  return h.startsWith("@") ? h.slice(1) : h;
}
