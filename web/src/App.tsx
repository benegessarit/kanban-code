import { useEffect, useState } from "react";
import { JoinScreen } from "./components/JoinScreen";
import { ChatRoom } from "./components/ChatRoom";
import { ThemeToggle } from "./components/ThemeToggle";
import { fetchAccessibleChannels, getToken } from "./lib/api";
import { loadHandle, saveHandle } from "./lib/handle";

type BootState =
  | { kind: "loading" }
  | { kind: "noToken" }
  | { kind: "error"; message: string }
  | { kind: "empty" }
  | { kind: "ready"; channelName: string };

export function App(): React.ReactElement {
  const [handle, setHandle] = useState<string | null>(null);
  const [boot, setBoot] = useState<BootState>({ kind: "loading" });

  useEffect(() => {
    if (!getToken()) { setBoot({ kind: "noToken" }); return; }
    setHandle(loadHandle());
    (async () => {
      try {
        const channels = await fetchAccessibleChannels();
        if (channels.length === 0) { setBoot({ kind: "empty" }); return; }
        // Multi-channel support lives in the server's API shape but the UI
        // currently renders the first (and only) channel. When we broaden to
        // many, this is where a channel-picker would land.
        setBoot({ kind: "ready", channelName: channels[0].name });
      } catch (err) {
        setBoot({ kind: "error", message: err instanceof Error ? err.message : String(err) });
      }
    })();
  }, []);

  // ChatRoom renders its own toggle in the header; everywhere else gets a
  // fixed one in the corner so users can flip themes even before joining.
  const floatingToggle = (
    <ThemeToggle className="fixed top-3 right-3 bg-background/70 backdrop-blur" />
  );

  if (boot.kind === "noToken") {
    return (
      <div className="min-h-full grid place-items-center p-8">
        {floatingToggle}
        <div className="max-w-md space-y-2 text-center">
          <h1 className="text-lg font-semibold">Missing share token</h1>
          <p className="text-sm text-muted-foreground">
            This page needs a <code>?token=…</code> parameter. Ask the host for
            the full share link.
          </p>
        </div>
      </div>
    );
  }

  if (boot.kind === "error") {
    return (
      <div className="min-h-full grid place-items-center p-8">
        {floatingToggle}
        <div className="max-w-md space-y-3 text-center">
          <h1 className="text-lg font-semibold">Can't reach this share</h1>
          <p className="text-sm text-muted-foreground">{boot.message}</p>
          <p className="text-xs text-muted-foreground">
            The share link may have expired, or the host closed it.
          </p>
        </div>
      </div>
    );
  }

  if (boot.kind === "empty") {
    return (
      <div className="min-h-full grid place-items-center p-8">
        {floatingToggle}
        <div className="max-w-md space-y-2 text-center">
          <h1 className="text-lg font-semibold">No channels available</h1>
          <p className="text-sm text-muted-foreground">
            This share link no longer points at any channels.
          </p>
        </div>
      </div>
    );
  }

  if (boot.kind === "loading") return <div />;

  if (!handle) {
    return (
      <>
        {floatingToggle}
        <JoinScreen
          channelName={boot.channelName}
          onJoin={(h) => { saveHandle(h); setHandle(h); }}
        />
      </>
    );
  }

  return <ChatRoom channelName={boot.channelName} myHandle={handle} />;
}
