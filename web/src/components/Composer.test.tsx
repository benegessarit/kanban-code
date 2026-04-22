import { describe, test, expect, vi } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { Composer } from "./Composer";

describe("Composer", () => {
  test("sends on Enter with trimmed body and clears the field", async () => {
    const onSend = vi.fn().mockResolvedValue(undefined);
    const user = userEvent.setup();
    render(<Composer channelName="general" mentionCandidates={[]} onSend={onSend} />);
    const ta = screen.getByPlaceholderText(/message #general/i);
    await user.type(ta, "  hello world  {Enter}");
    expect(onSend).toHaveBeenCalledWith("hello world", []);
    expect((ta as HTMLTextAreaElement).value).toBe("");
  });

  test("Shift+Enter inserts a newline instead of sending", async () => {
    const onSend = vi.fn().mockResolvedValue(undefined);
    const user = userEvent.setup();
    render(<Composer channelName="general" mentionCandidates={[]} onSend={onSend} />);
    const ta = screen.getByPlaceholderText(/message #general/i) as HTMLTextAreaElement;
    await user.type(ta, "line 1{Shift>}{Enter}{/Shift}line 2");
    expect(onSend).not.toHaveBeenCalled();
    expect(ta.value).toBe("line 1\nline 2");
  });

  test("typing @ opens the mention popover with channel members", async () => {
    const user = userEvent.setup();
    render(
      <Composer
        channelName="general"
        mentionCandidates={["alice", "ai_gateway_sergey", "ai_gateway_alexis"]}
        onSend={vi.fn()}
      />,
    );
    const ta = screen.getByPlaceholderText(/message #general/i);
    await user.type(ta, "hi @ai");
    const listbox = await screen.findByRole("listbox", { name: /mention suggestions/i });
    expect(listbox).toBeInTheDocument();
    const options = screen.getAllByRole("option");
    expect(options.map((o) => o.textContent)).toEqual([
      "@ai_gateway_sergey", "@ai_gateway_alexis",
    ]);
  });

  test("Enter inside the picker inserts the selected handle (not send)", async () => {
    const onSend = vi.fn().mockResolvedValue(undefined);
    const user = userEvent.setup();
    render(
      <Composer
        channelName="general"
        mentionCandidates={["alice"]}
        onSend={onSend}
      />,
    );
    const ta = screen.getByPlaceholderText(/message #general/i) as HTMLTextAreaElement;
    await user.type(ta, "hi @al{Enter}");
    expect(ta.value).toBe("hi @alice ");
    expect(onSend).not.toHaveBeenCalled();
  });

  test("arrow keys navigate the picker", async () => {
    const user = userEvent.setup();
    render(
      <Composer
        channelName="general"
        mentionCandidates={["ai_gateway_sergey", "ai_gateway_alexis"]}
        onSend={vi.fn()}
      />,
    );
    const ta = screen.getByPlaceholderText(/message #general/i);
    await user.type(ta, "@ai");
    // Default: first option selected.
    let selected = screen.getByRole("option", { selected: true });
    expect(selected).toHaveTextContent("@ai_gateway_sergey");
    await user.keyboard("{ArrowDown}");
    selected = screen.getByRole("option", { selected: true });
    expect(selected).toHaveTextContent("@ai_gateway_alexis");
    // Wrap-around.
    await user.keyboard("{ArrowDown}");
    selected = screen.getByRole("option", { selected: true });
    expect(selected).toHaveTextContent("@ai_gateway_sergey");
  });

  test("pasting an image attaches a thumbnail and sending forwards the file", async () => {
    // jsdom doesn't implement URL.createObjectURL by default, nor a full
    // DataTransfer API — so we fire a synthetic paste event with a hand-built
    // clipboardData object.
    const origCreate = URL.createObjectURL;
    URL.createObjectURL = vi.fn(() => "blob:fake");
    try {
      const onSend = vi.fn().mockResolvedValue(undefined);
      const user = userEvent.setup();
      render(<Composer channelName="general" mentionCandidates={[]} onSend={onSend} />);
      const ta = screen.getByPlaceholderText(/message #general/i);
      const file = new File([new Uint8Array([0x89, 0x50, 0x4e, 0x47])], "pic.png", {
        type: "image/png",
      });
      fireEvent.paste(ta, {
        clipboardData: { files: [file], items: [], types: [], getData: () => "" },
      });
      expect(await screen.findByRole("button", { name: /remove pic\.png/i })).toBeInTheDocument();
      await user.type(ta, "look{Enter}");
      expect(onSend).toHaveBeenCalledWith("look", [file]);
    } finally {
      URL.createObjectURL = origCreate;
    }
  });

  test("send button is disabled when text is empty", () => {
    render(<Composer channelName="general" mentionCandidates={[]} onSend={vi.fn()} />);
    expect(screen.getByRole("button", { name: /send/i })).toBeDisabled();
  });

  test("send button is disabled when component is disabled (share expired)", async () => {
    const user = userEvent.setup();
    render(<Composer channelName="general" mentionCandidates={[]} onSend={vi.fn()} disabled />);
    const ta = screen.getByPlaceholderText(/message #general/i) as HTMLTextAreaElement;
    expect(ta).toBeDisabled();
    await user.type(ta, "should not send");
    // Even with text, the button stays disabled.
    expect(screen.getByRole("button", { name: /send/i })).toBeDisabled();
  });
});
