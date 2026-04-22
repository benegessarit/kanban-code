import { useEffect, useRef } from "react";
import type { ChannelMessage } from "@/lib/types";
import { imageFilesystemPathToHttpUrl } from "@/lib/api";
import { cn } from "@/lib/utils";

interface Props {
  messages: ChannelMessage[];
  ownHandle: string;
}

function formatTs(iso: string): string {
  try {
    return new Date(iso).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
  } catch { return iso; }
}

/** Linkify http(s) URLs only. We don't render HTML — bodies are treated as
 *  plain text with clickable URLs. Matches the Swift client's approach. */
function renderBody(body: string): React.ReactNode {
  const parts: React.ReactNode[] = [];
  const re = /https?:\/\/[^\s<>"'\])*]*[^\s<>"'\]).,:;!?]/g;
  let last = 0;
  let m: RegExpExecArray | null;
  let i = 0;
  while ((m = re.exec(body)) !== null) {
    if (m.index > last) parts.push(body.slice(last, m.index));
    parts.push(
      <a
        key={`u${i++}`}
        href={m[0]}
        target="_blank"
        rel="noreferrer noopener"
        className="text-sky-400 underline decoration-sky-400/50 hover:decoration-sky-400"
      >
        {m[0]}
      </a>,
    );
    last = m.index + m[0].length;
  }
  if (last < body.length) parts.push(body.slice(last));
  return parts;
}

export function MessageList({ messages, ownHandle }: Props): React.ReactElement {
  const bottomRef = useRef<HTMLDivElement>(null);
  useEffect(() => {
    // `scrollIntoView` isn't implemented in jsdom; guard so tests don't crash.
    bottomRef.current?.scrollIntoView?.({ behavior: "smooth", block: "end" });
  }, [messages.length]);

  const realMessages = messages.filter((m) => m.type === "message" || m.type === undefined);

  return (
    <div
      role="log"
      aria-label="channel messages"
      className="flex-1 overflow-y-auto px-4 py-4 space-y-3"
    >
      {realMessages.length === 0 && (
        <div className="text-center text-sm text-muted-foreground py-12">
          No messages yet. Say hello.
        </div>
      )}
      {realMessages.map((m) => {
        const mine = m.from.handle === ownHandle;
        return (
          <div key={m.id} className="flex gap-3">
            <div className="min-w-0 flex-1 space-y-0.5">
              <div className="flex items-baseline gap-2">
                <span
                  className={cn(
                    "text-sm font-semibold",
                    mine ? "text-emerald-400" : "text-sky-400",
                  )}
                >
                  @{m.from.handle}
                </span>
                {m.source === "external" && (
                  <span className="text-[10px] uppercase tracking-wider text-amber-400/80 border border-amber-400/30 rounded px-1 py-0.5">
                    external
                  </span>
                )}
                <span className="text-xs text-muted-foreground" title={m.ts}>
                  {formatTs(m.ts)}
                </span>
              </div>
              <div className="text-sm whitespace-pre-wrap break-words">
                {renderBody(m.body)}
              </div>
              {m.imagePaths && m.imagePaths.length > 0 && (
                <div className="flex flex-wrap gap-2 pt-1">
                  {m.imagePaths.map((p, i) => {
                    const url = imageFilesystemPathToHttpUrl(p);
                    if (!url) return null;
                    return (
                      <a
                        key={`${m.id}-img-${i}`}
                        href={url}
                        target="_blank"
                        rel="noreferrer noopener"
                        className="block"
                      >
                        <img
                          src={url}
                          alt="attached image"
                          className="max-h-64 rounded border border-border/60 object-contain"
                          loading="lazy"
                        />
                      </a>
                    );
                  })}
                </div>
              )}
            </div>
          </div>
        );
      })}
      <div ref={bottomRef} />
    </div>
  );
}
