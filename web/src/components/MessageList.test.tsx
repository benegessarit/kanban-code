import { describe, test, expect } from "vitest";
import { render, screen } from "@testing-library/react";
import { MessageList } from "./MessageList";
import type { ChannelMessage } from "@/lib/types";

const at = (t: string) => t; // readability alias

function msg(partial: Partial<ChannelMessage> & { id: string; body: string; handle: string }): ChannelMessage {
  return {
    id: partial.id,
    ts: partial.ts ?? new Date().toISOString(),
    from: { cardId: null, handle: partial.handle },
    body: partial.body,
    type: "message",
    source: partial.source,
    imagePaths: partial.imagePaths,
  };
}

describe("MessageList", () => {
  test("renders the empty state when no real messages", () => {
    render(<MessageList messages={[]} ownHandle="ext_dana" />);
    expect(screen.getByText(/no messages yet/i)).toBeInTheDocument();
  });

  test("filters out join/leave/system entries", () => {
    render(
      <MessageList
        messages={[
          { id: "j1", ts: "2026-04-20T00:00:00Z", from: { cardId: null, handle: "x" }, body: "joined", type: "join" },
          msg({ id: "m1", body: "hi", handle: "alice" }),
        ]}
        ownHandle={at("ext_dana")}
      />,
    );
    expect(screen.queryByText(/joined/i)).not.toBeInTheDocument();
    expect(screen.getByText("hi")).toBeInTheDocument();
  });

  test("flags external messages with an 'external' badge", () => {
    render(
      <MessageList
        messages={[msg({ id: "m1", body: "untrusted", handle: "ext_dana", source: "external" })]}
        ownHandle="ext_dana"
      />,
    );
    expect(screen.getByText(/external/i)).toBeInTheDocument();
  });

  test("internal messages do NOT show the external badge", () => {
    render(
      <MessageList
        messages={[msg({ id: "m1", body: "trusted", handle: "alice" })]}
        ownHandle="ext_dana"
      />,
    );
    expect(screen.queryByText(/external/i)).not.toBeInTheDocument();
  });

  test("linkifies http(s) URLs", () => {
    render(
      <MessageList
        messages={[msg({ id: "m1", body: "see https://example.com", handle: "alice" })]}
        ownHandle="ext_dana"
      />,
    );
    const link = screen.getByRole("link", { name: "https://example.com" });
    expect(link).toHaveAttribute("href", "https://example.com");
    expect(link).toHaveAttribute("target", "_blank");
  });

  test("own messages get a distinct style (green handle color class)", () => {
    const { container } = render(
      <MessageList
        messages={[
          msg({ id: "m1", body: "hello", handle: "ext_dana" }),
          msg({ id: "m2", body: "reply", handle: "alice" }),
        ]}
        ownHandle="ext_dana"
      />,
    );
    // Each message renders its handle in a span; verify the mine-class is
    // applied only to the message from ext_dana.
    const spans = container.querySelectorAll("span.font-semibold");
    expect(spans).toHaveLength(2);
    expect(spans[0].className).toMatch(/emerald/);
    expect(spans[1].className).toMatch(/sky/);
  });
});
