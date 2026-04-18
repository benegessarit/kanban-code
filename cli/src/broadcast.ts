/**
 * Broadcast layer: fan out a channel message to every member's tmux session
 * except the sender. Auto-detect the sender's card from $TMUX when not passed.
 *
 * The actual `tmux paste-buffer + Enter` is delegated to an injectable
 * `Sender` function so tests can run without a real tmux server.
 */

import { execSync } from "node:child_process";
import { pasteTmuxPrompt } from "./data.js";
import type { Link } from "./types.js";
import {
  Channel,
  ChannelMessage,
  appendDirectMessage,
  getChannel,
  persistMessageImages,
  sendMessage,
} from "./channels.js";
import { formatHandle } from "./handles.js";

// ── Types / injectables ───────────────────────────────────────────────

export interface Sender {
  (tmuxSession: string, text: string): { ok: boolean; error?: string };
}

export interface LiveSessionProbe {
  (tmuxSession: string): boolean;
}

export interface FanOutOptions {
  sender?: Sender;
  liveSessionProbe?: LiveSessionProbe;
  includeOfflineInReport?: boolean;
}

export interface FanOutResult {
  delivered: { handle: string; tmuxSession: string }[];
  skippedOffline: { handle: string; reason: string }[];
  skippedSender: { handle: string };
}

// ── Resolve current card from tmux ───────────────────────────────────

/**
 * Resolve the tmux session name the CLI is running INSIDE. Returns undefined
 * if not running inside tmux.
 */
export function currentTmuxSessionName(): string | undefined {
  // Two channels: $TMUX_PANE + `tmux display-message -p '#S'`.
  if (!process.env.TMUX) return undefined;
  try {
    const out = execSync(`tmux display-message -p '#S'`, { encoding: "utf-8" }).trim();
    return out || undefined;
  } catch {
    return undefined;
  }
}

/** Find the card whose primary tmux session matches the given session name. */
export function cardForTmuxSession(links: Link[], sessionName: string): Link | undefined {
  for (const l of links) {
    if (l.tmuxLink?.sessionName === sessionName) return l;
    if (l.tmuxLink?.extraSessions?.includes(sessionName)) return l;
  }
  return undefined;
}

// ── Formatting ────────────────────────────────────────────────────────

export function formatChannelBroadcast(
  channel: string,
  handle: string,
  body: string,
  imageCount: number = 0
): string {
  const hint = imageCount > 0 ? ` [${imageCount} image(s) attached]` : "";
  return `[Message from #${channel} ${formatHandle(handle)}]: ${body}${hint}`;
}

export function formatDirectMessage(
  handle: string,
  body: string,
  imageCount: number = 0
): string {
  const hint = imageCount > 0 ? ` [${imageCount} image(s) attached]` : "";
  return `[DM from ${formatHandle(handle)}]: ${body}${hint}`;
}

// ── Fan-out ───────────────────────────────────────────────────────────

/**
 * Deliver a message to every member's tmux session except the sender.
 *
 * The caller is responsible for having already persisted the message to the
 * channel log. Returns a report describing who was reached and who was skipped.
 */
export function fanOutChannelMessage(
  channel: Channel,
  msg: ChannelMessage,
  links: Link[],
  opts: FanOutOptions = {}
): FanOutResult {
  const sender: Sender = opts.sender ?? pasteTmuxPrompt;
  const probe: LiveSessionProbe = opts.liveSessionProbe ?? ((_name) => true);

  const delivered: { handle: string; tmuxSession: string }[] = [];
  const skippedOffline: { handle: string; reason: string }[] = [];

  for (const member of channel.members) {
    // Skip sender (both by cardId and by handle — the latter catches the human user case).
    if (
      (msg.from.cardId !== null && member.cardId === msg.from.cardId) ||
      (msg.from.cardId === null && member.cardId === null) ||
      member.handle === msg.from.handle
    ) {
      continue;
    }
    if (member.cardId === null) {
      // The human user has no tmux session — the UI handles their display.
      continue;
    }
    const link = links.find((l) => l.id === member.cardId);
    const session = link?.tmuxLink?.sessionName;
    if (!session) {
      skippedOffline.push({ handle: member.handle, reason: "no tmux session" });
      continue;
    }
    if (!probe(session)) {
      skippedOffline.push({ handle: member.handle, reason: "tmux session offline" });
      continue;
    }
    const text = formatChannelBroadcast(
      channel.name,
      msg.from.handle,
      msg.body,
      msg.imagePaths?.length ?? 0
    );
    const res = sender(session, text);
    if (res.ok) {
      delivered.push({ handle: member.handle, tmuxSession: session });
    } else {
      skippedOffline.push({ handle: member.handle, reason: res.error ?? "send failed" });
    }
  }

  return {
    delivered,
    skippedOffline,
    skippedSender: { handle: msg.from.handle },
  };
}

/** Convenience: send + fan-out in one call. Persists the message and broadcasts. */
export function sendAndFanOut(
  channelName: string,
  from: { cardId: string | null; handle: string },
  body: string,
  links: Link[],
  baseDir?: string,
  opts: FanOutOptions = {},
  imagePaths: string[] = []
): { msg: ChannelMessage; result: FanOutResult } {
  const msg = sendMessage(channelName, from, body, baseDir, imagePaths);
  const channel = getChannel(channelName, baseDir)!;
  const result = fanOutChannelMessage(channel, msg, links, opts);
  return { msg, result };
}

// ── Direct message fan-out ───────────────────────────────────────────

export function sendDirectMessage(
  from: { cardId: string | null; handle: string },
  to: { cardId: string | null; handle: string },
  body: string,
  links: Link[],
  baseDir?: string,
  opts: FanOutOptions = {},
  imagePaths: string[] = []
): { msg: ChannelMessage & { to: typeof to }; delivered: boolean; error?: string } {
  const sender: Sender = opts.sender ?? pasteTmuxPrompt;
  const probe: LiveSessionProbe = opts.liveSessionProbe ?? ((_n) => true);
  const id = `msg_${Date.now().toString(36)}`;
  const persisted = persistMessageImages(id, imagePaths, baseDir);
  const msg: ChannelMessage & { to: typeof to } = {
    id,
    ts: new Date().toISOString(),
    from,
    to,
    body,
    type: "message",
    ...(persisted.length > 0 ? { imagePaths: persisted } : {}),
  };
  appendDirectMessage(msg, baseDir);
  if (to.cardId === null) {
    return { msg, delivered: false, error: "recipient has no tmux session (user)" };
  }
  const link = links.find((l) => l.id === to.cardId);
  const session = link?.tmuxLink?.sessionName;
  if (!session) return { msg, delivered: false, error: "recipient has no tmux session" };
  if (!probe(session)) return { msg, delivered: false, error: "recipient offline" };
  const text = formatDirectMessage(from.handle, body, persisted.length);
  const r = sender(session, text);
  return { msg, delivered: r.ok, error: r.error };
}
