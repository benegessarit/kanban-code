import { test, describe, beforeEach, afterEach } from "node:test";
import { strict as assert } from "node:assert";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawn } from "node:child_process";

import { createChannel, joinChannel, readMessages } from "./channels.js";
import { parseDuration, runShare, warmDns, warmTunnel } from "./share-cli.js";

let base: string;
function tmp(): string { return mkdtempSync(join(tmpdir(), "kanban-share-cli-test-")); }

describe("parseDuration", () => {
  test("accepts m, h, s suffixes", () => {
    assert.equal(parseDuration("5m"), 5 * 60_000);
    assert.equal(parseDuration("1h"), 60 * 60_000);
    assert.equal(parseDuration("30s"), 30_000);
    assert.equal(parseDuration("6h"), 6 * 60 * 60_000);
  });

  test("treats bare number as minutes", () => {
    assert.equal(parseDuration("15"), 15 * 60_000);
  });

  test("rejects garbage", () => {
    assert.throws(() => parseDuration(""));
    assert.throws(() => parseDuration("abc"));
    assert.throws(() => parseDuration("-5m"));
    assert.throws(() => parseDuration("0"));
  });
});

describe("warmDns", () => {
  test("returns once both resolve4 AND lookup succeed", async () => {
    let resolveCalls = 0;
    let lookupCalls = 0;
    await warmDns("example.com", {
      intervalMs: 20,
      timeoutMs: 1000,
      resolveImpl: async () => { resolveCalls++; return ["1.2.3.4"]; },
      lookupImpl: async () => { lookupCalls++; },
    });
    assert.equal(resolveCalls, 1);
    assert.equal(lookupCalls, 1);
  });

  test("keeps polling until upstream record appears", async () => {
    let resolveCalls = 0;
    // First 3 resolve calls fail, 4th returns a record.
    const resolveImpl = async (): Promise<string[]> => {
      resolveCalls++;
      if (resolveCalls < 4) throw new Error("NXDOMAIN");
      return ["1.2.3.4"];
    };
    await warmDns("example.com", {
      intervalMs: 20,
      timeoutMs: 2000,
      resolveImpl,
      lookupImpl: async () => {},
    });
    assert.equal(resolveCalls, 4);
  });

  test("keeps polling when OS cache still holds NXDOMAIN after upstream ready", async () => {
    let lookupCalls = 0;
    const lookupImpl = async (): Promise<void> => {
      lookupCalls++;
      if (lookupCalls < 3) throw new Error("EAI_NONAME");
    };
    await warmDns("example.com", {
      intervalMs: 20,
      timeoutMs: 2000,
      resolveImpl: async () => ["1.2.3.4"],
      lookupImpl,
    });
    assert.equal(lookupCalls, 3);
  });

  test("times out with a clear error when nothing ever resolves", async () => {
    await assert.rejects(
      warmDns("never.example.invalid", {
        intervalMs: 20,
        timeoutMs: 200,
        resolveImpl: async () => { throw new Error("NXDOMAIN"); },
        lookupImpl: async () => { throw new Error("EAI_NONAME"); },
      }),
      /dns-warmup-timeout/,
    );
    assert.throws(() => parseDuration("5d"));
  });
});

describe("warmTunnel", () => {
  // Minimal fake `Response` — just what warmTunnel reads.
  function fakeRes(status: number, headers: Record<string, string> = {}) {
    return { status, headers: { get: (n: string) => headers[n.toLowerCase()] ?? null } };
  }

  test("returns when the Express server answers (detected via x-powered-by)", async () => {
    let n = 0;
    await warmTunnel("https://tunnel.example/", {
      intervalMs: 10,
      timeoutMs: 2000,
      fetchImpl: async () => { n++; return fakeRes(401, { "x-powered-by": "Express" }); },
    });
    assert.equal(n, 1);
  });

  test("keeps polling through Cloudflare's edge 404 (Error 1033) until the connector wires up", async () => {
    let n = 0;
    await warmTunnel("https://tunnel.example/", {
      intervalMs: 10,
      timeoutMs: 2000,
      fetchImpl: async () => {
        n++;
        // Cloudflare's Error 1033 comes back with server: cloudflare and no
        // x-powered-by header.
        if (n < 3) return fakeRes(404, { server: "cloudflare" });
        return fakeRes(401, { "x-powered-by": "Express" });
      },
    });
    assert.equal(n, 3);
  });

  test("swallows fetch errors and keeps polling", async () => {
    let n = 0;
    await warmTunnel("https://tunnel.example/", {
      intervalMs: 10,
      timeoutMs: 2000,
      fetchImpl: async () => {
        n++;
        if (n < 2) throw new Error("ECONNREFUSED");
        return fakeRes(401, { "x-powered-by": "Express" });
      },
    });
    assert.equal(n, 2);
  });

  test("times out if the tunnel never becomes reachable", async () => {
    await assert.rejects(
      warmTunnel("https://tunnel.example/", {
        intervalMs: 10,
        timeoutMs: 100,
        fetchImpl: async () => fakeRes(404, { server: "cloudflare" }),
      }),
      /tunnel-warmup-timeout/,
    );
  });

  // Make sure the probe hits /api/channels, not the root (which serves HTML
  // from express.static and lacks `x-powered-by` on some Express versions).
  test("probes /api/channels (a known Express route) not the root", async () => {
    let lastUrl = "";
    await warmTunnel("https://tunnel.example/", {
      intervalMs: 10,
      timeoutMs: 1000,
      fetchImpl: async (u: string) => { lastUrl = u; return fakeRes(401, { "x-powered-by": "Express" }); },
    });
    assert.ok(lastUrl.endsWith("/api/channels"), `expected probe at /api/channels, got ${lastUrl}`);
  });
});

describe("runShare", () => {
  beforeEach(() => {
    base = tmp();
    createChannel("general", {}, base);
    joinChannel("general", { cardId: "card_A", handle: "alice" }, base);
    joinChannel("general", { cardId: "card_B", handle: "bob" }, base);
  });
  afterEach(() => { rmSync(base, { recursive: true, force: true }); });

  // Factory for a fake tunnel starter that doesn't call cloudflared. It spawns
  // /bin/sh with a tiny script so we exercise the real ChildProcess plumbing
  // in startCloudflaredTunnel-like shape.
  function fakeTunnel(url: string): {
    start: (opts: { port: number }) => Promise<{ url: string; child: import("node:child_process").ChildProcess; stop: () => Promise<void> }>;
    spawnedPorts: number[];
  } {
    const spawnedPorts: number[] = [];
    return {
      spawnedPorts,
      start: async ({ port }) => {
        spawnedPorts.push(port);
        const child = spawn("/bin/sh", ["-c", `trap 'exit 0' TERM; while true; do sleep 0.1; done`]);
        const stop = async (): Promise<void> => {
          if (child.exitCode !== null) return;
          await new Promise<void>((res) => {
            child.once("exit", () => res());
            try { child.kill("SIGTERM"); } catch { res(); }
          });
        };
        return { url, child, stop };
      },
    };
  }

  test("starts server, spawns tunnel on the assigned port, writes 4 metadata lines", async () => {
    const lines: string[] = [];
    const { start, spawnedPorts } = fakeTunnel("https://test-share.trycloudflare.com");

    const handle = await runShare({
      channelName: "general",
      durationMs: 60_000,
      loadLinks: () => [],
      sender: () => ({ ok: true }),
      baseDir: base,
      startTunnel: start as unknown as Parameters<typeof runShare>[0]["startTunnel"],
      warmDnsImpl: async () => {},

      warmTunnelImpl: async () => {},
      writeLine: (l) => lines.push(l),
      writeError: () => {},
    });

    // Metadata lines in the expected order.
    assert.equal(lines.length, 4);
    assert.match(lines[0], /^url: https:\/\/test-share\.trycloudflare\.com\/\?token=tk_/);
    assert.match(lines[1], /^token: tk_[a-f0-9]{32}$/);
    assert.match(lines[2], /^port: \d+$/);
    assert.match(lines[3], /^expiresAt: \d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/);

    // Tunnel was pointed at the HTTP server's port.
    const announcedPort = Number(lines[2].replace("port: ", ""));
    assert.deepEqual(spawnedPorts, [announcedPort]);
    assert.equal(announcedPort, handle.port);

    await handle.stop();
    await handle.done;
  });

  test("token is embedded in the published URL", async () => {
    const lines: string[] = [];
    const { start } = fakeTunnel("https://abc.trycloudflare.com");
    const handle = await runShare({
      channelName: "general",
      durationMs: 60_000,
      loadLinks: () => [],
      sender: () => ({ ok: true }),
      baseDir: base,
      startTunnel: start as unknown as Parameters<typeof runShare>[0]["startTunnel"],
      warmDnsImpl: async () => {},

      warmTunnelImpl: async () => {},
      writeLine: (l) => lines.push(l),
      writeError: () => {},
    });
    assert.ok(lines[0].includes(handle.token));
    await handle.stop();
  });

  test("end-to-end: POST /send through the actual server reaches the fanout sender", async () => {
    const lines: string[] = [];
    const tmuxPastes: { session: string; text: string }[] = [];
    const { start } = fakeTunnel("https://e2e.trycloudflare.com");
    const handle = await runShare({
      channelName: "general",
      durationMs: 60_000,
      loadLinks: () => [
        {
          id: "card_A", name: "card_A", column: "in_progress",
          createdAt: new Date().toISOString(), updatedAt: new Date().toISOString(),
          tmuxLink: { sessionName: "session-a" },
          isRemote: false, prLinks: [],
          manualOverrides: { worktreePath: false, tmuxSession: false, name: false, column: false, prLink: false, issueLink: false },
          source: "manual", manuallyArchived: false,
        } as unknown as Parameters<typeof runShare>[0]["loadLinks"] extends () => (infer T)[] ? T : never,
        {
          id: "card_B", name: "card_B", column: "in_progress",
          createdAt: new Date().toISOString(), updatedAt: new Date().toISOString(),
          tmuxLink: { sessionName: "session-b" },
          isRemote: false, prLinks: [],
          manualOverrides: { worktreePath: false, tmuxSession: false, name: false, column: false, prLink: false, issueLink: false },
          source: "manual", manuallyArchived: false,
        } as unknown as Parameters<typeof runShare>[0]["loadLinks"] extends () => (infer T)[] ? T : never,
      ],
      sender: (s, t) => { tmuxPastes.push({ session: s, text: t }); return { ok: true }; },
      baseDir: base,
      startTunnel: start as unknown as Parameters<typeof runShare>[0]["startTunnel"],
      warmDnsImpl: async () => {},

      warmTunnelImpl: async () => {},
      writeLine: (l) => lines.push(l),
      writeError: () => {},
    });

    // Make a real HTTP call against the local server.
    const res = await fetch(`http://127.0.0.1:${handle.port}/api/channels/general/send?token=${handle.token}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ handle: "dana", body: "hello from e2e" }),
    });
    assert.equal(res.status, 200);
    const body = await res.json() as { msg: { source?: string; from: { handle: string } } };
    assert.equal(body.msg.source, "external");
    assert.equal(body.msg.from.handle, "ext_dana");

    // Fanout hit every agent with the warning-prefixed broadcast.
    assert.equal(tmuxPastes.length, 2);
    for (const p of tmuxPastes) {
      assert.ok(p.text.startsWith("The message below"), `paste to ${p.session} should be flagged external`);
      assert.ok(p.text.includes("[Message from #general @ext_dana]: hello from e2e"));
    }

    // And the jsonl was appended to.
    const log = readMessages("general", base);
    const last = log.filter((m) => m.type === "message").pop()!;
    assert.equal(last.body, "hello from e2e");
    assert.equal(last.source, "external");

    await handle.stop();
  });

  test("stop() is idempotent and tears the tunnel + server down", async () => {
    const { start } = fakeTunnel("https://stop.trycloudflare.com");
    const handle = await runShare({
      channelName: "general",
      durationMs: 60_000,
      loadLinks: () => [],
      sender: () => ({ ok: true }),
      baseDir: base,
      startTunnel: start as unknown as Parameters<typeof runShare>[0]["startTunnel"],
      warmDnsImpl: async () => {},

      warmTunnelImpl: async () => {},
      writeLine: () => {},
      writeError: () => {},
    });
    const port = handle.port;

    await handle.stop();
    await handle.stop(); // 2nd call is a no-op
    await handle.done;

    // Server is down: connect() should fail fast.
    await assert.rejects(
      fetch(`http://127.0.0.1:${port}/api/channels/general/info?token=${handle.token}`)
    );
  });

  test("auto-expires when the duration elapses", async () => {
    const { start } = fakeTunnel("https://expire.trycloudflare.com");
    const handle = await runShare({
      channelName: "general",
      durationMs: 150, // 150ms — plenty to start up, short to expire
      loadLinks: () => [],
      sender: () => ({ ok: true }),
      baseDir: base,
      startTunnel: start as unknown as Parameters<typeof runShare>[0]["startTunnel"],
      warmDnsImpl: async () => {},

      warmTunnelImpl: async () => {},
      writeLine: () => {},
      writeError: () => {},
    });
    // done resolves once the auto-expire timer fires + teardown completes.
    const deadline = Date.now() + 3000;
    await Promise.race([
      handle.done,
      new Promise((_r, reject) => setTimeout(() => reject(new Error("did not auto-expire")), deadline - Date.now())),
    ]);
  });

  test("if cloudflared fails to publish a URL, server is torn down and error is thrown", async () => {
    const failingStart = async () => { throw new Error("cloudflared exploded"); };
    await assert.rejects(
      runShare({
        channelName: "general",
        durationMs: 60_000,
        loadLinks: () => [],
        sender: () => ({ ok: true }),
        baseDir: base,
        startTunnel: failingStart as unknown as Parameters<typeof runShare>[0]["startTunnel"],
        writeLine: () => {},
        writeError: () => {},
      }),
      /cloudflared exploded/
    );
  });
});
