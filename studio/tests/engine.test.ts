import { describe, expect, it } from "vitest";
import {
  DemoRewriter,
  antiSlop,
  chatCompletionsURL,
  systemPrompt,
  temperatureFor,
  tokenCostLabel,
  validateAPIKey,
  validateSelection,
} from "../src/engine";

const rewriter = new DemoRewriter();

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
});
