import { getToken } from "./api";

const STORAGE_KEY_PREFIX = "kanban-share-handle:";

/** Matches the server's regex (cli/src/share-server.ts). */
const HANDLE_RE = /^[a-z0-9][a-z0-9_-]{0,47}$/i;

export function validateHandle(raw: string): { ok: true; value: string } | { ok: false; error: string } {
  const trimmed = raw.trim();
  if (!trimmed) return { ok: false, error: "please enter a name" };
  // Strip a leading ext_ so round-tripping the server's stored form works.
  const core = trimmed.replace(/^ext_/i, "");
  if (!HANDLE_RE.test(core)) {
    return {
      ok: false,
      error: "use letters, digits, _ or - (must start with a letter or digit)",
    };
  }
  return { ok: true, value: core.toLowerCase() };
}

/** The token namespaces sessionStorage so opening two different share links
 *  in the same browser doesn't cross-contaminate handles. */
function storageKey(): string {
  return STORAGE_KEY_PREFIX + getToken();
}

export function loadHandle(): string | null {
  try { return sessionStorage.getItem(storageKey()); } catch { return null; }
}

export function saveHandle(handle: string): void {
  try { sessionStorage.setItem(storageKey(), handle); } catch { /* quota etc. */ }
}

export function clearHandle(): void {
  try { sessionStorage.removeItem(storageKey()); } catch { /* */ }
}
