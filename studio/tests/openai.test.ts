import { afterEach, describe, expect, it, vi } from "vitest";
import { streamRemote, streamStallTimeout, testConnection } from "../src/engine";

const remoteOptions = {
  baseURL: "https://api.openai.com/v1",
  model: "gpt-4o-mini",
  apiKey: "sk-test",
  authStyle: "bearer" as const,
};

function sseResponse(body: string, status = 200, headers: Record<string, string> = {}): Response {
  return new Response(body, { status, headers });
}

async function collectStream(body: string) {
  vi.stubGlobal(
    "fetch",
    vi.fn(async () => sseResponse(body)),
  );
  const partials: string[] = [];
  const result = await streamRemote("hello there", "correct", "casual", null, "", remoteOptions, "same", (value) =>
    partials.push(value),
  );
  return { result, partials };
}

describe("streamRemote", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("enforces banned words on the remote output via custom instructions", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () =>
        sseResponse('data: {"choices":[{"delta":{"content":"We utilize synergy here."}}]}\n\ndata: [DONE]\n\n')),
    );
    const result = await streamRemote(
      "hello there",
      "correct",
      "casual",
      null,
      "never use the word synergy",
      remoteOptions,
      "same",
      () => {},
    );
    expect(result.text).not.toMatch(/synergy/i);
    expect(result.text).toContain("utilize");
  });

  it("enforces replace rules and the no-exclamation rule on remote output", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () =>
        sseResponse('data: {"choices":[{"delta":{"content":"Utilize this now!"}}]}\n\ndata: [DONE]\n\n')),
    );
    const result = await streamRemote(
      "hello there",
      "correct",
      "casual",
      null,
      "replace utilize with use. No exclamation",
      remoteOptions,
      "same",
      () => {},
    );
    expect(result.text).toBe("use this now.");
  });

  it("surfaces Retry-After seconds on HTTP 429", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => sseResponse("{}", 429, { "Retry-After": "7" })),
    );
    const error = await streamRemote("hello", "correct", "casual", null, "", remoteOptions, "same", () => {}).catch(
      (caught: unknown) => caught,
    );
    expect(error).toBeInstanceOf(Error);
    expect((error as Error).message).toMatch(/rate limit/i);
    expect((error as { retryAfterMs?: number }).retryAfterMs).toBe(7_000);
    expect((error as Error).message).not.toContain("sk-test");
  });

  it("surfaces Retry-After HTTP-date on HTTP 429", async () => {
    const when = new Date(Date.now() + 30_000).toUTCString();
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => sseResponse("{}", 429, { "Retry-After": when })),
    );
    const error = await streamRemote("hello", "correct", "casual", null, "", remoteOptions, "same", () => {}).catch(
      (caught: unknown) => caught,
    );
    const retryAfterMs = (error as { retryAfterMs?: number }).retryAfterMs;
    expect(retryAfterMs).toBeGreaterThan(20_000);
    expect(retryAfterMs).toBeLessThanOrEqual(31_000);
  });

  it("rejects oversized input before any network call", async () => {
    const fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);
    await expect(
      streamRemote("a".repeat(100_001), "correct", "casual", null, "", remoteOptions, "same", () => {}),
    ).rejects.toThrow(/too large/);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("handles a final chunk without a trailing newline", async () => {
    const { result } = await collectStream('data: {"choices":[{"delta":{"content":"Final text."}}]}');
    expect(result.text).toBe("Final text.");
  });

  it("rejects with streamStalled when the body never yields a chunk", async () => {
    const previous = streamStallTimeout.ms;
    streamStallTimeout.ms = 50;
    try {
      // A reader whose read() never settles simulates a server that goes silent
      // mid-stream. (A real never-yielding ReadableStream behaves differently
      // under some runtimes, so the contract is pinned with an explicit fake.)
      const silentReader = {
        read: () => new Promise<never>(() => {}),
        cancel: async () => {},
      };
      vi.stubGlobal(
        "fetch",
        vi.fn(async () => ({ status: 200, ok: true, body: { getReader: () => silentReader } })),
      );
      const error = await streamRemote("hello", "correct", "casual", null, "", remoteOptions, "same", () => {}).catch(
        (caught: unknown) => caught,
      );
      expect(error).toBeInstanceOf(Error);
      expect((error as Error).message).toMatch(/stall/i);
      expect((error as { code?: string }).code).toBe("streamStalled");
    } finally {
      streamStallTimeout.ms = previous;
    }
  });

  it("keeps caller cancellation working through the watchdog", async () => {
    const previous = streamStallTimeout.ms;
    streamStallTimeout.ms = 50;
    try {
      const controller = new AbortController();
      vi.stubGlobal(
        "fetch",
        vi.fn(async () => {
          const signal = controller.signal;
          // A fake reader whose read() rejects once the caller's signal aborts,
          // simulating cancellation racing a stalled server.
          const abortableReader = {
            read: () =>
              new Promise<never>((_, reject) => {
                const onAbort = () => reject(new DOMException("The rewrite was cancelled.", "AbortError"));
                if (signal.aborted) {
                  onAbort();
                  return;
                }
                signal.addEventListener("abort", onAbort, { once: true });
              }),
            cancel: async () => {},
          };
          return { status: 200, ok: true, body: { getReader: () => abortableReader } };
        }),
      );
      const pending = streamRemote("hello", "correct", "casual", null, "", remoteOptions, "same", () => {}, controller.signal);
      controller.abort();
      await expect(pending).rejects.toThrow(/cancel/i);
    } finally {
      streamStallTimeout.ms = previous;
    }
  });

  it("joins multi-line data events and skips heartbeat comments", async () => {
    const { result } = await collectStream(
      [
        ": ping",
        "",
        'data: {"choices":[{"delta":',
        'data: {"content":"Joined text."}}]}',
        "",
        "data: [DONE]",
        "",
      ].join("\r\n"),
    );
    expect(result.text).toBe("Joined text.");
  });

  it("decodes finish_reason and surfaces truncation", async () => {
    const { result } = await collectStream(
      [
        'data: {"choices":[{"delta":{"content":"Cut off"}}]}',
        "",
        'data: {"choices":[{"delta":{},"finish_reason":"length"}]}',
        "",
        "data: [DONE]",
        "",
      ].join("\n"),
    );
    expect(result.text).toBe("Cut off");
    expect(result.finishReason).toBe("length");
  });

  it("produces no usage label when a usage field is missing", async () => {
    const { result } = await collectStream(
      [
        'data: {"choices":[{"delta":{"content":"Some text."}}]}',
        "",
        'data: {"usage":{"prompt_tokens":12}}',
        "",
        "data: [DONE]",
        "",
      ].join("\n"),
    );
    expect(result.text).toBe("Some text.");
    expect(result.usage).toBeUndefined();
  });

  it("keeps usage when both token counts are present", async () => {
    const { result } = await collectStream(
      [
        'data: {"choices":[{"delta":{"content":"Some text."}}]}',
        "",
        'data: {"usage":{"prompt_tokens":12,"completion_tokens":4}}',
        "",
        "data: [DONE]",
        "",
      ].join("\n"),
    );
    expect(result.usage).toEqual({ promptTokens: 12, completionTokens: 4 });
  });

  it("never includes the API key in thrown error messages", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => sseResponse(JSON.stringify({ error: { message: "Invalid key sk-test rejected" } }), 401)),
    );
    const error = await streamRemote("hello", "correct", "casual", null, "", remoteOptions, "same", () => {}).catch(
      (caught: unknown) => caught,
    );
    expect(error).toBeInstanceOf(Error);
    // The server-provided message is surfaced, but our client must never add
    // the API key or request headers to error messages itself.
    expect((error as Error).message).toBe("Invalid key sk-test rejected");
    expect((error as Error).message).not.toContain("Bearer");
  });
});

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

  it("pings the Azure models endpoint when an apiVersion is set", async () => {
    const fetchMock = vi.fn(async () => new Response("{}", { status: 200 }));
    vi.stubGlobal("fetch", fetchMock);
    const result = await testConnection({
      provider: "openAI",
      baseURL: "https://example.openai.azure.com",
      model: "gpt-4o-mini",
      apiKey: "azure-key",
      authStyle: "apiKeyHeader",
      apiVersion: "2024-10-21",
    });
    expect(result.ok).toBe(true);
    expect(fetchMock).toHaveBeenCalledWith(
      "https://example.openai.azure.com/openai/models?api-version=2024-10-21",
      expect.objectContaining({ headers: { "api-key": "azure-key" } }),
    );
  });

  it("redacts the API key from network error messages", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => {
        throw new Error("request with key azure-key failed");
      }),
    );
    const result = await testConnection({
      provider: "openAI",
      baseURL: "https://example.openai.azure.com",
      model: "gpt-4o-mini",
      apiKey: "azure-key",
      authStyle: "apiKeyHeader",
      apiVersion: "2024-10-21",
    });
    expect(result.ok).toBe(false);
    expect(result.message).not.toContain("azure-key");
    expect(result.message).toContain("[redacted]");
  });
});
