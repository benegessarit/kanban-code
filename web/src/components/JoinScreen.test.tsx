import { describe, test, expect, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { JoinScreen } from "./JoinScreen";

describe("JoinScreen", () => {
  test("renders channel name and asks for a display name", () => {
    render(<JoinScreen channelName="general" onJoin={vi.fn()} />);
    expect(screen.getByRole("heading", { name: /join #general/i })).toBeInTheDocument();
    expect(screen.getByLabelText(/display name/i)).toBeInTheDocument();
  });

  test("calls onJoin with the normalized handle when Join is clicked", async () => {
    const onJoin = vi.fn();
    const user = userEvent.setup();
    render(<JoinScreen channelName="general" onJoin={onJoin} />);
    await user.type(screen.getByLabelText(/display name/i), "Dana");
    await user.click(screen.getByRole("button", { name: /join channel/i }));
    expect(onJoin).toHaveBeenCalledWith("dana");
  });

  test("Enter key submits", async () => {
    const onJoin = vi.fn();
    const user = userEvent.setup();
    render(<JoinScreen channelName="general" onJoin={onJoin} />);
    await user.type(screen.getByLabelText(/display name/i), "alice{Enter}");
    expect(onJoin).toHaveBeenCalledWith("alice");
  });

  test("shows an error for invalid handles and does not call onJoin", async () => {
    const onJoin = vi.fn();
    const user = userEvent.setup();
    render(<JoinScreen channelName="general" onJoin={onJoin} />);
    await user.type(screen.getByLabelText(/display name/i), "bad/name");
    await user.click(screen.getByRole("button", { name: /join channel/i }));
    expect(screen.getByRole("alert")).toBeInTheDocument();
    expect(onJoin).not.toHaveBeenCalled();
  });

  test("Join button is disabled for empty names", () => {
    render(<JoinScreen channelName="general" onJoin={vi.fn()} />);
    expect(screen.getByRole("button", { name: /join channel/i })).toBeDisabled();
  });
});
