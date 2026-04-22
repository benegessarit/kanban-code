import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, waitFor } from "@testing-library/react";
import { App } from "./App";

/** Each test swaps the query string so App's token-check + channel discovery
 *  talks to a known URL + a mocked fetch. */
function withQuery(qs: string, fn: () => void): void {
  const orig = window.location.href;
  window.history.replaceState(null, "", `/${qs}`);
  try { fn(); } finally {
    window.history.replaceState(null, "", orig);
  }
}

describe("App bootstrap flow", () => {
  const origFetch = globalThis.fetch;
  beforeEach(() => {
    sessionStorage.clear();
  });
  afterEach(() => {
    globalThis.fetch = origFetch;
    vi.restoreAllMocks();
  });

  test("when ?token is missing, shows a 'Missing share token' screen", async () => {
    withQuery("", () => {
      render(<App />);
    });
    expect(await screen.findByText(/missing share token/i)).toBeInTheDocument();
  });

  test("discovery response drives the channel name rendered in JoinScreen", async () => {
    // Mock the /api/channels response to return a channel called "test".
    const fetchMock = vi.fn(async (input: RequestInfo | URL) => {
      const url = typeof input === "string" ? input : input.toString();
      if (url.includes("/api/channels?")) {
        return new Response(
          JSON.stringify({ channels: [{ name: "test", members: [], remainingMs: 300000, expiresAt: new Date(Date.now() + 300000).toISOString() }] }),
          { status: 200, headers: { "Content-Type": "application/json" } },
        );
      }
      return new Response("not mocked", { status: 404 });
    });
    globalThis.fetch = fetchMock as unknown as typeof fetch;

    withQuery("?token=tk_abc", () => {
      render(<App />);
    });
    // JoinScreen renders "Join #<channelName>"
    expect(await screen.findByRole("heading", { name: /join #test/i })).toBeInTheDocument();
    // It must NOT default to "general"
    expect(screen.queryByText(/join #general/i)).not.toBeInTheDocument();
  });

  test("empty channel list shows the 'no channels available' screen", async () => {
    const fetchMock = vi.fn(async () =>
      new Response(JSON.stringify({ channels: [] }), {
        status: 200, headers: { "Content-Type": "application/json" },
      }),
    );
    globalThis.fetch = fetchMock as unknown as typeof fetch;
    withQuery("?token=tk_abc", () => {
      render(<App />);
    });
    expect(await screen.findByText(/no channels available/i)).toBeInTheDocument();
  });

  test("network error shows a friendly error screen, not a crash", async () => {
    globalThis.fetch = vi.fn(async () => new Response("nope", { status: 500 })) as unknown as typeof fetch;
    withQuery("?token=tk_abc", () => {
      render(<App />);
    });
    await waitFor(() => {
      expect(screen.getByText(/can't reach this share/i)).toBeInTheDocument();
    });
  });
});
