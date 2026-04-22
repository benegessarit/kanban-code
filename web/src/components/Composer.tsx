import { useRef, useState, useEffect, useCallback } from "react";
import { Button } from "./ui/button";
import { Send, X, Image as ImageIcon } from "lucide-react";
import {
  activeMentionQuery,
  filteredMentionMatches,
  insertMention,
} from "@/lib/mentions";
import { cn } from "@/lib/utils";

interface Props {
  channelName: string;
  mentionCandidates: string[];
  disabled?: boolean;
  onSend: (body: string, imageFiles: File[]) => Promise<void>;
}

export function Composer({ channelName, mentionCandidates, disabled, onSend }: Props): React.ReactElement {
  const [text, setText] = useState("");
  const [pendingImages, setPendingImages] = useState<File[]>([]);
  const [mentionSelected, setMentionSelected] = useState(0);
  const textareaRef = useRef<HTMLTextAreaElement>(null);

  const mentionQuery = activeMentionQuery(text);
  const matches = mentionQuery !== null
    ? filteredMentionMatches(mentionQuery, mentionCandidates).slice(0, 6)
    : [];
  const pickerOpen = matches.length > 0 && mentionQuery !== null;

  useEffect(() => {
    if (mentionSelected >= matches.length) setMentionSelected(0);
  }, [matches.length, mentionSelected]);

  // Auto-grow textarea height to its content, capped.
  useEffect(() => {
    const el = textareaRef.current;
    if (!el) return;
    el.style.height = "auto";
    el.style.height = Math.min(el.scrollHeight, 160) + "px";
  }, [text]);

  const doSend = useCallback(async () => {
    const body = text.trim();
    if (!body) return;
    await onSend(body, pendingImages);
    setText("");
    setPendingImages([]);
  }, [text, pendingImages, onSend]);

  function onKeyDown(e: React.KeyboardEvent<HTMLTextAreaElement>): void {
    if (pickerOpen) {
      if (e.key === "ArrowDown") {
        e.preventDefault();
        setMentionSelected((i) => (i + 1) % matches.length);
        return;
      }
      if (e.key === "ArrowUp") {
        e.preventDefault();
        setMentionSelected((i) => (i - 1 + matches.length) % matches.length);
        return;
      }
      if (e.key === "Enter" && !e.shiftKey) {
        e.preventDefault();
        const picked = matches[mentionSelected] ?? matches[0];
        setText((t) => insertMention(t, picked));
        setMentionSelected(0);
        return;
      }
      if (e.key === "Escape") {
        e.preventDefault();
        // dismiss picker by inserting a space after @ so query stops matching
        setText((t) => t + " ");
        return;
      }
    }
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      void doSend();
    }
  }

  function onPaste(e: React.ClipboardEvent<HTMLTextAreaElement>): void {
    const files = Array.from(e.clipboardData.files).filter((f) => f.type.startsWith("image/"));
    if (files.length > 0) {
      e.preventDefault();
      setPendingImages((prev) => [...prev, ...files]);
    }
  }

  function removeImage(idx: number): void {
    setPendingImages((prev) => prev.filter((_, i) => i !== idx));
  }

  return (
    <div className="border-t bg-background/80 backdrop-blur p-3 relative">
      {/* Mention picker — absolutely positioned above the composer so it
          doesn't push layout up as more matches appear. */}
      {pickerOpen && (
        <div
          role="listbox"
          aria-label="mention suggestions"
          className="absolute bottom-full left-3 mb-2 min-w-[160px] max-w-[280px] rounded-md border bg-popover text-popover-foreground shadow-lg p-1"
        >
          {matches.map((h, i) => (
            <button
              key={h}
              role="option"
              aria-selected={i === mentionSelected}
              type="button"
              onClick={() => {
                setText((t) => insertMention(t, h));
                textareaRef.current?.focus();
              }}
              onMouseEnter={() => setMentionSelected(i)}
              className={cn(
                "w-full text-left px-2 py-1 rounded text-sm",
                i === mentionSelected ? "bg-primary text-primary-foreground" : "hover:bg-accent",
              )}
            >
              @{h}
            </button>
          ))}
        </div>
      )}

      {pendingImages.length > 0 && (
        <div className="flex gap-2 pb-2 overflow-x-auto">
          {pendingImages.map((f, i) => (
            <div key={i} className="relative shrink-0">
              <img
                src={URL.createObjectURL(f)}
                alt={f.name}
                className="h-12 w-12 rounded object-cover border"
              />
              <button
                type="button"
                onClick={() => removeImage(i)}
                className="absolute -top-1 -right-1 bg-destructive text-destructive-foreground rounded-full p-0.5"
                aria-label={`remove ${f.name}`}
              >
                <X className="h-3 w-3" />
              </button>
            </div>
          ))}
        </div>
      )}

      <div className="flex items-end gap-2">
        <textarea
          ref={textareaRef}
          value={text}
          onChange={(e) => setText(e.target.value)}
          onKeyDown={onKeyDown}
          onPaste={onPaste}
          disabled={disabled}
          placeholder={`Message #${channelName}`}
          rows={1}
          className="flex-1 resize-none bg-background rounded-md border px-3 py-2 text-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
        />
        {pendingImages.length === 0 && (
          <Button
            type="button"
            variant="ghost"
            size="icon"
            aria-label="Image paste hint"
            title="Paste images with ⌘V"
            disabled
          >
            <ImageIcon className="h-4 w-4 opacity-40" />
          </Button>
        )}
        <Button
          type="button"
          size="icon"
          disabled={disabled || !text.trim()}
          onClick={() => void doSend()}
          aria-label="Send"
        >
          <Send className="h-4 w-4" />
        </Button>
      </div>
    </div>
  );
}
