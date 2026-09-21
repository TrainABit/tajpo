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

  it("does not treat style guidance as a banned word", () => {
    // "avoid long sentences" is style guidance — the word "long" must survive.
    expect(applyCustomInstructions("Avoid long sentences in this long document.", "avoid long sentences")).toContain(
      "long",
    );
    expect(applyCustomInstructions("Avoid long sentences in this long document.", "avoid long sentences")).toBe(
      "Avoid long sentences in this long document.",
    );
  });

  it("still removes words named explicitly with 'the word' or quotes", () => {
    expect(applyCustomInstructions("This has synergy in it.", "never use the word synergy")).not.toMatch(/synergy/i);
    expect(applyCustomInstructions("This has synergy in it.", 'never use "synergy"')).not.toMatch(/synergy/i);
    expect(applyCustomInstructions("This has synergy in it.", "avoid the word synergy")).not.toMatch(/synergy/i);
  });

  it("honors multiple banned words in one instruction", () => {
    const result = applyCustomInstructions(
      "Synergy and jargon live here.",
      "never use the word synergy and never use the word jargon",
    );
    expect(result).not.toMatch(/synergy/i);
    expect(result).not.toMatch(/jargon/i);
    expect(result).toContain("live here");
  });

  it("replaces words per 'replace X with Y' instructions", () => {
    expect(applyCustomInstructions("Please utilize this tool.", "replace utilize with use")).toBe(
      "Please use this tool.",
    );
    expect(applyCustomInstructions("Utilize the jargon-free path.", "replace the word Utilize with Use")).toBe(
      "Use the jargon-free path.",
    );
  });

  it("applies multiple replace rules in one instruction", () => {
    const result = applyCustomInstructions(
      "We utilize synergy here.",
      "replace utilize with use and replace synergy with teamwork",
    );
    expect(result).toBe("We use teamwork here.");
  });

  it("does not misread banned-word instructions as replace rules", () => {
    // "never use the word X" must delete X, not attempt a replacement.
    expect(applyCustomInstructions("This has synergy in it.", "never use the word synergy")).not.toMatch(/synergy/i);
    // A replace rule must not delete the target word either.
    expect(applyCustomInstructions("We utilize this.", "replace utilize with use")).toContain("use");
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

  it("handles empty inputs on either side of wordDiff", () => {
    const allAdded = wordDiff("", "one two");
    expect(allAdded.every((token) => token.kind === "add")).toBe(true);
    expect(allAdded.map((token) => token.text).join("")).toBe("one two");
    const allDeleted = wordDiff("one two", "");
    expect(allDeleted.every((token) => token.kind === "del")).toBe(true);
    expect(allDeleted.map((token) => token.text).join("")).toBe("one two");
    expect(wordDiff("", "")).toEqual([]);
  });

  it("marks duplicate tokens with the expected shape", () => {
    const tokens = wordDiff("very very good", "very good");
    expect(tokens).toEqual([
      { text: "very", kind: "same" },
      { text: " ", kind: "same" },
      { text: "very", kind: "del" },
      { text: "good", kind: "add" },
      { text: " ", kind: "del" },
      { text: "good", kind: "del" },
    ]);
    expect(tokens.filter((token) => token.kind === "same").length).toBeGreaterThan(0);
  });

  it("diffs long inputs quickly", () => {
    const left = Array.from({ length: 10_000 }, (_, i) => `word${i}`).join(" ");
    const right = Array.from({ length: 10_000 }, (_, i) => (i % 7 === 0 ? `changed${i}` : `word${i}`)).join(" ");
    const start = performance.now();
    const tokens = wordDiff(left, right);
    const elapsed = performance.now() - start;
    expect(tokens.length).toBeGreaterThan(0);
    expect(elapsed).toBeLessThan(500);
  });
});
