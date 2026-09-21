import { describe, expect, it } from "vitest";
import {
  DemoRewriter,
  antiSlop,
  chatCompletionsURL,
  estimateTokenCount,
  finishReasonLabel,
  parseRetryAfter,
  systemPrompt,
  temperatureFor,
  tokenCostLabel,
  validateAPIKey,
  validateRemoteInput,
  validateSelection,
} from "../src/engine";

const rewriter = new DemoRewriter();

describe("usage and finish-reason helpers", () => {
  it("estimates tokens from text length", () => {
    expect(estimateTokenCount("")).toBe(0);
    expect(estimateTokenCount("abcd")).toBe(1);
    expect(estimateTokenCount("a".repeat(9))).toBe(3);
  });

  it("labels finish reasons for users", () => {
    expect(finishReasonLabel(undefined)).toBe("");
    expect(finishReasonLabel("stop")).toBe("");
    expect(finishReasonLabel("length")).toMatch(/truncated/i);
    expect(finishReasonLabel("content_filter")).toMatch(/content filter/i);
    expect(finishReasonLabel("tool_calls")).toMatch(/ended early/i);
  });
});

describe("prompts", () => {
  it("keeps correction narrow and always applies anti-slop", () => {
    const prompt = systemPrompt("correct", "casual");
    expect(prompt).toContain("Correct only");
    expect(prompt).toContain("Do not change meaning");
    expect(prompt).toContain(antiSlop);
  });

  it("includes custom instructions, tone lock, and length", () => {
    const prompt = systemPrompt(
      "changeTone",
      "confident",
      { id: "p", name: "House", systemPrompt: "Use short sentences." },
      "Never use the word synergy.",
      "shorter",
    );
    expect(prompt).toContain("confident");
    expect(prompt).toContain("must not override the requested confident tone");
    expect(prompt).toContain("Never use the word synergy.");
    expect(prompt).toContain("shorter than the source");
  });

  it("uses zero temperature for correct and bullets", () => {
    expect(temperatureFor("correct")).toBe(0);
    expect(temperatureFor("bullets")).toBe(0);
    expect(temperatureFor("improve")).toBe(0.3);
  });

  it("instructs the model to return the full replacement text for continueWriting", () => {
    const prompt = systemPrompt("continueWriting", "casual");
    expect(prompt).toContain("COMPLETE text");
    expect(prompt).toContain("verbatim");
    expect(prompt).toContain("Never return only the continuation");
  });
});

describe("validators", () => {
  it("rejects empty and oversized selections", () => {
    expect(() => validateSelection("   \n\t")).toThrow(/No selected text/);
    expect(() => validateSelection("a".repeat(100_001))).toThrow(/too large/);
    expect(validateSelection("Hello there")).toBe("Hello there");
  });

  it("trims API keys", () => {
    expect(() => validateAPIKey("   ")).toThrow(/API key/);
    expect(validateAPIKey("  sk-test  ")).toBe("sk-test");
  });

  it("builds OpenAI and Azure URLs", () => {
    expect(chatCompletionsURL("https://api.openai.com/v1/", "gpt-4o-mini")).toBe(
      "https://api.openai.com/v1/chat/completions",
    );
    expect(chatCompletionsURL("https://example.openai.azure.com", "gpt-4o-mini", "2024-10-21")).toBe(
      "https://example.openai.azure.com/openai/deployments/gpt-4o-mini/chat/completions?api-version=2024-10-21",
    );
    expect(() => chatCompletionsURL("  ", "gpt-4o-mini")).toThrow(/invalid/);
  });

  it("labels token cost for known models", () => {
    expect(tokenCostLabel("gpt-4o-mini", 1_000_000, 1_000_000)).toBe("2000000 tokens · about $0.7500");
    expect(tokenCostLabel("unknown-local", 2, 3)).toBe("5 tokens");
  });

  it("produces no cost label when a token count is missing", () => {
    expect(tokenCostLabel("gpt-4o-mini", 120, undefined)).toBe("");
    expect(tokenCostLabel("gpt-4o-mini", undefined, 45)).toBe("");
    expect(tokenCostLabel("gpt-4o-mini", undefined, undefined)).toBe("");
  });

  it("parses Retry-After headers in seconds and HTTP-date form", () => {
    expect(parseRetryAfter("5", 0)).toBe(5_000);
    expect(parseRetryAfter(null, 0)).toBeUndefined();
    expect(parseRetryAfter("not-a-date", 0)).toBeUndefined();
    const date = new Date(60_000).toUTCString();
    expect(parseRetryAfter(date, 0)).toBe(60_000);
    expect(parseRetryAfter(date, 120_000)).toBe(0);
  });

  it("validates remote input like the demo path", () => {
    expect(() => validateRemoteInput("a".repeat(100_001))).toThrow(/too large/);
    expect(() => validateRemoteInput("   ")).toThrow(/No selected text/);
    expect(validateRemoteInput("Hello there")).toBe("Hello there");
  });
});

describe("demo rewriter", () => {
  it("corrects typos and standalone i", () => {
    expect(rewriter.rewrite("teh quick brown fox", "correct", "casual")).toBe("The quick brown fox");
    expect(rewriter.rewrite("i can do this", "correct", "casual")).toBe("I can do this");
  });

  it("strips hedges in the confident tone", () => {
    expect(rewriter.rewrite("i think we should really just go", "changeTone", "confident")).toBe("We should go");
  });

  it("simplifies latinate words after correction", () => {
    expect(rewriter.rewrite("Utilize the enviroment in order to commence", "simplify", "professional")).toBe(
      "Use the environment in order to start",
    );
  });

  it("shortens wordy phrases", () => {
    const result = rewriter.rewrite("We did this due to the fact that it was necessary", "shorten", "professional");
    expect(result).toContain("because");
    expect(result.toLowerCase()).not.toContain("due to the fact");
  });

  it("splits sentences into bullets", () => {
    expect(rewriter.rewrite("Hello there. This is a second sentence.", "bullets", "casual")).toBe(
      "- Hello there.\n- This is a second sentence.",
    );
  });

  it("expands with a deterministic closer", () => {
    expect(rewriter.rewrite("We need this.", "expand", "casual")).toBe(
      "We need this. That is the point to keep in view.",
    );
  });

  it("continues without dropping the source", () => {
    const result = rewriter.rewrite("Ship the rewrite panel.", "continueWriting", "casual");
    expect(result.startsWith("Ship the rewrite panel.")).toBe(true);
    expect(result).toContain("next step");
  });

  it("returns original + exactly one continuation for continueWriting", () => {
    const source = "Ship the rewrite panel. Then we ship the next one.";
    const result = rewriter.rewrite(source, "continueWriting", "casual");
    // Unified continuation contract: the result is the FULL replacement text —
    // the original passage first (verbatim), then exactly one continuation.
    expect(result.startsWith(source)).toBe(true);
    expect(result.length).toBeGreaterThan(source.length);
    // The source appears exactly once — no duplication before or after.
    expect(result.split(source).length - 1).toBe(1);
    const continuation = result.slice(source.length).trim();
    expect(continuation.length).toBeGreaterThan(0);
    expect(continuation.split(/(?<=[.!?])\s+/).filter(Boolean).length).toBe(1);
  });

  it("applies concise preset and shorter length", () => {
    const longer = rewriter.rewrite("We did this due to the fact that it was necessary", "correct", "professional");
    const concise = rewriter.rewrite("We did this due to the fact that it was necessary", "correct", "professional", {
      preset: { id: "concise", name: "Concise", systemPrompt: "Prefer short sentences and concrete verbs. Cut anything that does not carry information." },
    });
    expect(concise.toLowerCase()).not.toContain("due to the fact");
    expect(concise.length).toBeLessThanOrEqual(longer.length);
    expect(rewriter.rewrite("We need this.", "correct", "casual", { length: "longer" })).toContain(
      "That is the point to keep in view.",
    );
  });

  it("honors never-use-word and no-exclamation instructions", () => {
    const result = rewriter.rewrite("Tajpo is useful!", "correct", "casual", {
      customInstructions: 'never use the word Tajpo. No exclamation marks.',
    });
    expect(result.toLowerCase()).not.toContain("tajpo");
    expect(result).not.toContain("!");
  });

  it("fixes brief need agreement", () => {
    expect(rewriter.rewrite("this brief need to recieve comments", "correct", "professional")).toBe(
      "This brief needs to receive comments",
    );
  });

  it("leaves abbreviations, domains, and version numbers intact", () => {
    expect(rewriter.rewrite("use e.g. this approach", "correct", "casual")).toContain("e.g. this");
    expect(rewriter.rewrite("visit example.com today", "correct", "casual")).toContain("example.com");
    expect(rewriter.rewrite("Ship version 3.5 is ready", "correct", "casual")).toBe("Ship version 3.5 is ready");
    expect(rewriter.rewrite("ship v1.2a now", "correct", "casual")).toContain("v1.2a");
  });

  it("capitalizes unicode sentence starts", () => {
    expect(rewriter.rewrite("élève ton jeu", "correct", "casual")).toBe("Élève ton jeu");
    expect(rewriter.rewrite("über alles", "correct", "casual")).toBe("Über alles");
  });

  it("matches presets by identity, not prompt substrings", () => {
    const source = "We did this due to the fact that it was necessary";
    const baseline = rewriter.rewrite(source, "correct", "professional");
    // A custom preset whose prompt merely mentions concise phrasing must not
    // trigger the shorten transform.
    const untouched = rewriter.rewrite(source, "correct", "professional", {
      preset: { id: "house", name: "House", systemPrompt: "Prefer short sentences and concrete verbs." },
    });
    expect(untouched).toBe(baseline);
    // The built-in Concise preset still shortens by name/identity.
    const concise = rewriter.rewrite(source, "correct", "professional", {
      preset: { id: "concise", name: "Concise", systemPrompt: "Write elegantly, in full sentences." },
    });
    expect(concise.toLowerCase()).not.toContain("due to the fact");
    expect(concise.length).toBeLessThanOrEqual(baseline.length);
  });

  it("never expands bullet output with the longer length", () => {
    const source = "First point here. Second point there.";
    const bullets = rewriter.rewrite(source, "bullets", "casual");
    const longer = rewriter.rewrite(source, "bullets", "casual", { length: "longer" });
    expect(bullets).toContain("\n- ");
    expect(longer).toBe(bullets);
    expect(longer).not.toContain("That is the point to keep in view.");
  });
});
