/** Mirrors cli/src/channels.ts ChannelMessage. */
export interface ChannelMessage {
  id: string;
  ts: string;
  from: { cardId: string | null; handle: string };
  body: string;
  type?: "message" | "join" | "leave" | "system";
  imagePaths?: string[];
  source?: "external";
}

export interface ChannelInfo {
  name: string;
  members: { handle: string }[];
  remainingMs: number;
  expiresAt: string;
}
