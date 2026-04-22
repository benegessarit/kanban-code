import { useEffect, useState } from "react";
import { JoinScreen } from "./components/JoinScreen";
import { ChatRoom } from "./components/ChatRoom";
import { getChannelName, getToken } from "./lib/api";
import { loadHandle, saveHandle } from "./lib/handle";

export function App(): React.ReactElement {
  const [handle, setHandle] = useState<string | null>(null);
  const [ready, setReady] = useState(false);
  const channelName = getChannelName();

  useEffect(() => {
    const h = loadHandle();
    if (h) setHandle(h);
    setReady(true);
  }, []);

  if (!getToken()) {
    return (
      <div className="min-h-full grid place-items-center p-8">
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

  if (!ready) return <div />;

  if (!handle) {
    return (
      <JoinScreen
        channelName={channelName}
        onJoin={(h) => { saveHandle(h); setHandle(h); }}
      />
    );
  }

  return <ChatRoom channelName={channelName} myHandle={handle} />;
}
