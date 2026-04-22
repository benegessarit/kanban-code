import { describe, test, expect } from "vitest";
import { activeMentionQuery, filteredMentionMatches, insertMention } from "./mentions";

describe("activeMentionQuery", () => {
  test("returns the tail after @ when it's the last token", () => {
    expect(activeMentionQuery("hi @al")).toBe("al");
  });
  test("returns empty string for lone @", () => {
    expect(activeMentionQuery("@")).toBe("");
  });
  test("returns null when @ has a space after", () => {
    expect(activeMentionQuery("@alice ")).toBeNull();
  });
  test("returns null with no @", () => {
    expect(activeMentionQuery("hello world")).toBeNull();
  });
  test("returns null when @ is preceded by a letter (email / inline text)", () => {
    expect(activeMentionQuery("me@server")).toBeNull();
  });
  test("accepts @ at the start of the string", () => {
    expect(activeMentionQuery("@alice")).toBe("alice");
  });
  test("accepts @ after punctuation", () => {
    expect(activeMentionQuery("hi, @al")).toBe("al");
  });
  test("handles underscores and dashes in the handle", () => {
    expect(activeMentionQuery("hey @ai_gateway")).toBe("ai_gateway");
    expect(activeMentionQuery("hey @ai-gateway")).toBe("ai-gateway");
  });
});

describe("filteredMentionMatches", () => {
  const candidates = ["alice", "ai_gateway_sergey", "ai_gateway_alexis", "bob"];
  test("empty query returns all candidates", () => {
    expect(filteredMentionMatches("", candidates)).toEqual(candidates);
  });
  test("prefix match, case-insensitive", () => {
    expect(filteredMentionMatches("ai", candidates)).toEqual([
      "ai_gateway_sergey", "ai_gateway_alexis",
    ]);
    expect(filteredMentionMatches("AL", candidates)).toEqual(["alice"]);
  });
  test("no matches → empty", () => {
    expect(filteredMentionMatches("zz", candidates)).toEqual([]);
  });
});

describe("insertMention", () => {
  test("replaces @partial with @handle + trailing space", () => {
    expect(insertMention("hi @al", "alice")).toBe("hi @alice ");
  });
  test("works at start of input", () => {
    expect(insertMention("@al", "alice")).toBe("@alice ");
  });
  test("no-op when there's no @", () => {
    expect(insertMention("hello", "alice")).toBe("hello");
  });
});
