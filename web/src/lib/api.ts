import type { ChannelInfo, ChannelMessage } from "./types";

/** Every API call needs the share token, parsed from the current URL's
 *  query string. Token handling is centralized here so no other module
 *  has to think about it. */
export function getToken(): string {
  const params = new URLSearchParams(window.location.search);
  return params.get("token") ?? "";
}

/** Channel name is the first path segment after `/c/`, falling back to the
 *  route element stored in sessionStorage by the router. Default "general"
 *  only applies when literally nothing else is known — that's a router bug
 *  rather than a runtime fallback. */
export function getChannelName(): string {
  const params = new URLSearchParams(window.location.search);
  const q = params.get("channel");
  if (q) return q;
  const m = window.location.pathname.match(/\/c\/([^/]+)/);
  if (m) return m[1];
  return "general";
}

export interface SendBody {
  handle: string;
  body: string;
  imagePaths?: string[];
}

function authedUrl(path: string, extraParams: Record<string, string> = {}): string {
  const p = new URLSearchParams({ token: getToken(), ...extraParams });
  return `${path}?${p.toString()}`;
}

export async function fetchInfo(channel: string): Promise<ChannelInfo> {
  const res = await fetch(authedUrl(`/api/channels/${channel}/info`));
  if (!res.ok) throw new Error(`info: ${res.status}`);
  return res.json();
}

export async function fetchHistory(channel: string): Promise<ChannelMessage[]> {
  const res = await fetch(authedUrl(`/api/channels/${channel}/history`));
  if (!res.ok) throw new Error(`history: ${res.status}`);
  const body = (await res.json()) as { messages: ChannelMessage[] };
  return body.messages;
}

export async function sendMessage(channel: string, payload: SendBody): Promise<ChannelMessage> {
  const res = await fetch(authedUrl(`/api/channels/${channel}/send`), {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
  if (!res.ok) {
    const err = await res.text();
    throw new Error(`send failed: ${res.status} ${err}`);
  }
  const body = (await res.json()) as { msg: ChannelMessage };
  return body.msg;
}

export async function uploadImage(channel: string, file: Blob): Promise<string> {
  const res = await fetch(authedUrl(`/api/channels/${channel}/images`), {
    method: "POST",
    headers: { "Content-Type": file.type || "image/png" },
    body: file,
  });
  if (!res.ok) throw new Error(`image upload: ${res.status}`);
  const body = (await res.json()) as { path: string };
  return body.path;
}

/** Open the SSE stream. Returns the EventSource so callers can close it. */
export function openStream(channel: string, handle: string): EventSource {
  return new EventSource(authedUrl(`/api/channels/${channel}/stream`, { handle }));
}
