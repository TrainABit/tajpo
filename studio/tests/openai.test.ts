import { afterEach, describe, expect, it, vi } from "vitest";
import { testConnection } from "../src/engine";

describe("testConnection", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("reports the demo engine as ready without a network call", async () => {
    const fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);
    const result = await testConnection({
      provider: "demo",
      baseURL: "",
      model: "tajpo-demo",
      apiKey: "",
      authStyle: "none",
    });
    expect(result.ok).toBe(true);
    expect(result.message).toMatch(/demo engine is ready/i);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("pings /models for a remote provider", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => new Response("{}", { status: 200 })),
    );
    const result = await testConnection({
      provider: "localCompatible",
      baseURL: "http://127.0.0.1:11434/v1",
      model: "llama3.2",
      apiKey: "",
      authStyle: "none",
    });
    expect(result.ok).toBe(true);
    expect(result.message).toContain("11434");
  });

  it("surfaces an unreachable server", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => {
        throw new Error("connect ECONNREFUSED");
      }),
    );
    const result = await testConnection({
      provider: "openAI",
      baseURL: "https://api.openai.com/v1",
      model: "gpt-4o-mini",
      apiKey: "sk-test",
      authStyle: "bearer",
    });
    expect(result.ok).toBe(false);
    expect(result.message).toMatch(/ECONNREFUSED|did not respond/i);
  });
});
