import { useState } from "react";
import { Button } from "./ui/button";
import { Input } from "./ui/input";
import { validateHandle } from "@/lib/handle";

interface JoinScreenProps {
  channelName: string;
  onJoin: (handle: string) => void;
}

export function JoinScreen({ channelName, onJoin }: JoinScreenProps): React.ReactElement {
  const [name, setName] = useState("");
  const [error, setError] = useState<string | null>(null);

  function submit(): void {
    const res = validateHandle(name);
    if (!res.ok) { setError(res.error); return; }
    onJoin(res.value);
  }

  return (
    <div className="min-h-full grid place-items-center p-8">
      <div className="w-full max-w-md space-y-6 bg-card border rounded-xl p-6 shadow-xl">
        <div className="space-y-2">
          <h1 className="text-xl font-semibold">Join #{channelName}</h1>
          <p className="text-sm text-muted-foreground">
            Pick a display name. Messages you send will be clearly flagged as
            coming from an external contributor to protect the team.
          </p>
        </div>
        <div className="space-y-2">
          <label htmlFor="join-name" className="text-sm font-medium">Display name</label>
          <Input
            id="join-name"
            value={name}
            onChange={(e) => { setName(e.target.value); if (error) setError(null); }}
            onKeyDown={(e) => { if (e.key === "Enter") submit(); }}
            placeholder="dana"
            autoFocus
            autoComplete="off"
          />
          {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
          <p className="text-xs text-muted-foreground">
            Letters, digits, underscore, dash. Your handle will appear as
            <span className="font-mono"> @ext_&lt;name&gt;</span> inside the channel.
          </p>
        </div>
        <Button className="w-full" onClick={submit} disabled={!name.trim()}>
          Join channel
        </Button>
      </div>
    </div>
  );
}
