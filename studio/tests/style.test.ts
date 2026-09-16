import { describe, expect, it } from "vitest";
import {
  applyCustomInstructions,
  applyReplacement,
  countWords,
  filterHistory,
  redoReplacement,
  undoReplacement,
  wordDiff,
  type HistoryEntry,
} from "../src/engine";

describe("style helpers", () => {
  it("removes a forbidden word and exclamation marks", () => {
    expect(applyCustomInstructions("Please utilize this!", "never use the word utilize. No exclamation")).toBe(
      "Please this.",
    );
    expect(applyCustomInstructions("Avoid synergy here", 'avoid the word synergy')).not.toMatch(/synergy/i);
  });

  it("applies, undoes, and redoes a replacement", () => {
    const first = applyReplacement("hello world today", 6, 11, "planet");
    expect(first.next).toBe("hello planet today");
    expect(undoReplacement(first.next, first.entry)).toBe("hello world today");
    expect(redoReplacement("hello world today", first.entry)).toBe("hello planet today");
  });

  it("filters history by query and action", () => {
    const entries: HistoryEntry[] = [
      { id: "1", createdAt: "2026-01-01", action: "correct", tone: "casual", original: "teh fox", result: "The fox" },
      { id: "2", createdAt: "2026-01-02", action: "shorten", tone: "professional", original: "hello", result: "Hi" },
    ];
    expect(filterHistory(entries, "fox", "all")).toHaveLength(1);
    expect(filterHistory(entries, "", "shorten")).toHaveLength(1);
    expect(filterHistory(entries, "missing", "all")).toHaveLength(0);
  });

  it("diffs added and removed words", () => {
    const tokens = wordDiff("hello world", "hello planet");
    expect(tokens.some((token) => token.kind === "del" && token.text === "world")).toBe(true);
    expect(tokens.some((token) => token.kind === "add" && token.text === "planet")).toBe(true);
    expect(countWords("one two three")).toBe(3);
    expect(countWords("   ")).toBe(0);
  });
});
