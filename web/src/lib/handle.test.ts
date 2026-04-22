import { describe, test, expect, beforeEach } from "vitest";
import { validateHandle, loadHandle, saveHandle, clearHandle } from "./handle";

function withToken(token: string, fn: () => void): void {
  // sessionStorage namespacing keys off the current URL token. JSDOM doesn't
  // let you redefine `window.location.search` directly, but history.replaceState
  // IS allowed and mutates window.location in place.
  const origUrl = window.location.href;
  window.history.replaceState(null, "", `/?token=${token}`);
  try { fn(); } finally {
    window.history.replaceState(null, "", origUrl);
  }
}

describe("validateHandle", () => {
  test("accepts a simple name", () => {
    expect(validateHandle("dana")).toEqual({ ok: true, value: "dana" });
  });
  test("lowercases", () => {
    expect(validateHandle("Dana")).toEqual({ ok: true, value: "dana" });
  });
  test("strips a leading ext_ so saved handles round-trip", () => {
    expect(validateHandle("ext_dana")).toEqual({ ok: true, value: "dana" });
  });
  test("rejects empty", () => {
    expect(validateHandle("")).toEqual({ ok: false, error: expect.any(String) });
    expect(validateHandle("   ")).toEqual({ ok: false, error: expect.any(String) });
  });
  test("rejects bad characters", () => {
    expect(validateHandle("evil/handle")).toMatchObject({ ok: false });
    expect(validateHandle("with spaces")).toMatchObject({ ok: false });
    expect(validateHandle("name!")).toMatchObject({ ok: false });
  });
  test("rejects names starting with _ or -", () => {
    expect(validateHandle("_dana")).toMatchObject({ ok: false });
    expect(validateHandle("-dana")).toMatchObject({ ok: false });
  });
  test("permits underscores and dashes in the middle", () => {
    expect(validateHandle("d_a-n_a")).toEqual({ ok: true, value: "d_a-n_a" });
  });
});

describe("session storage (token-namespaced)", () => {
  beforeEach(() => { sessionStorage.clear(); });

  test("load returns null before any save", () => {
    withToken("abc", () => {
      expect(loadHandle()).toBeNull();
    });
  });

  test("save then load round-trips", () => {
    withToken("abc", () => {
      saveHandle("dana");
      expect(loadHandle()).toBe("dana");
    });
  });

  test("tokens are independent — same browser, different token, empty storage", () => {
    withToken("abc", () => saveHandle("dana"));
    withToken("xyz", () => {
      expect(loadHandle()).toBeNull();
    });
  });

  test("clear removes the current token's handle only", () => {
    withToken("abc", () => saveHandle("alice"));
    withToken("xyz", () => saveHandle("bob"));
    withToken("abc", () => clearHandle());
    withToken("abc", () => expect(loadHandle()).toBeNull());
    withToken("xyz", () => expect(loadHandle()).toBe("bob"));
  });
});
