import { systemPrompt, temperatureFor } from "./prompts";
import type { LLMAuthStyle, LLMProvider, RewriteAction, RewriteLength, RewriteTone, WritingPreset } from "./types";
import { chatCompletionsURL, parseRetryAfter, TajpoError, validateRemoteInput } from "./validators";
import type { RewriteResultLike } from "./demoRewriter";
import { applyCustomInstructions } from "./style";

export interface RemoteClientOptions {
  baseURL: string;
  model: string;
  apiKey: string;
  authStyle: "bearer" | "apiKeyHeader" | "none";
  apiVersion?: string;
}

interface StreamEvent {
  choices?: { delta?: { content?: string }; finish_reason?: string | null }[];
  error?: { message?: string };
  usage?: { prompt_tokens?: number; completion_tokens?: number };
}

/** Default silence window for the streaming liveness watchdog. If no new
 *  chunk arrives within this window, the stream is treated as stalled. */
export const STREAM_STALL_TIMEOUT_MS = 30_000;

// Mutable holder so tests can shrink the deadline without touching the
// documented default above. streamRemote reads `streamStallTimeout.ms` on
// every read.
export const streamStallTimeout = { ms: STREAM_STALL_TIMEOUT_MS };

export async function streamRemote(
  text: string,
  action: RewriteAction,
  tone: RewriteTone,
  preset: WritingPreset | null,
  customInstructions: string,
  options: RemoteClientOptions,
  length: RewriteLength = "same",
  onPartial: (value: string) => void,
  signal?: AbortSignal,
): Promise<RewriteResultLike> {
  // Apply the same selection validation as the demo path so oversized input
  // never goes straight to a paid API.
  validateRemoteInput(text);

  const url = chatCompletionsURL(options.baseURL, options.model, options.apiVersion);
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (options.authStyle === "bearer" && options.apiKey) {
    headers.Authorization = `Bearer ${options.apiKey}`;
  }
  if (options.authStyle === "apiKeyHeader" && options.apiKey) {
    headers["api-key"] = options.apiKey;
  }

  const response = await fetch(url, {
    method: "POST",
    headers,
    signal,
    body: JSON.stringify({
      model: options.model,
      temperature: temperatureFor(action),
      stream: true,
      stream_options: { include_usage: true },
      messages: [
        { role: "system", content: systemPrompt(action, tone, preset, customInstructions, length) },
        { role: "user", content: text },
      ],
    }),
  });

  if (response.status === 429) {
    throw new TajpoError("rateLimited", "The model rate limit was reached. Wait a moment and retry.", {
      retryAfterMs: parseRetryAfter(response.headers?.get?.("Retry-After") ?? null),
    });
  }
  if (!response.ok || !response.body) {
    // Note: never include the API key or request headers in error messages.
    const body = await response.text();
    throw new TajpoError("api", parseAPIError(body, response.status));
  }

  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  let result = "";
  let sawDone = false;
  let usage: { promptTokens?: number; completionTokens?: number } | undefined;
  let finishReason: string | undefined;

  const handleEvent = (event: StreamEvent) => {
    if (event.error?.message) throw new TajpoError("api", event.error.message);
    if (event.usage) {
      // Keep token fields optional — a partial usage object must not be
      // zero-filled into a misleading cost label.
      usage = {
        ...(event.usage.prompt_tokens !== undefined ? { promptTokens: event.usage.prompt_tokens } : {}),
        ...(event.usage.completion_tokens !== undefined
          ? { completionTokens: event.usage.completion_tokens }
          : {}),
      };
    }
    const choice = event.choices?.[0];
    if (choice?.finish_reason) finishReason = choice.finish_reason;
    const delta = choice?.delta?.content;
    if (delta) {
      result += delta;
      onPartial(result);
    }
  };

  const processBuffer = (flush: boolean): void => {
    const lines = buffer.split("\n");
    // Keep a trailing partial line unless we are flushing the final chunk,
    // which may arrive without a trailing newline.
    buffer = flush ? "" : (lines.pop() ?? "");
    let dataLines: string[] = [];
    const flushEvent = (): void => {
      if (dataLines.length === 0) return;
      const payload = dataLines.join("\n").trim();
      dataLines = [];
      if (!payload) return;
      if (payload === "[DONE]") {
        sawDone = true;
        return;
      }
      try {
        handleEvent(JSON.parse(payload) as StreamEvent);
      } catch (error) {
        if (error instanceof TajpoError) throw error;
        // Ignore malformed keep-alive or partial JSON payloads.
      }
    };
    for (const line of lines) {
      const trimmed = line.replace(/\r$/, "").trim();
      if (!trimmed) {
        // A blank line terminates an SSE event.
        flushEvent();
        continue;
      }
      // Comment/heartbeat lines (e.g. ": ping") carry no data.
      if (trimmed.startsWith(":")) continue;
      if (trimmed.startsWith("data:")) {
        dataLines.push(trimmed.slice(5).trim());
      }
    }
    flushEvent();
  };

  // Streaming liveness watchdog: race every read against a silence deadline.
  // If the server stops sending chunks (without ending the stream), abort and
  // surface a TajpoError with code "streamStalled". Cancellation via the
  // caller's signal still works because an aborted body rejects read() itself.
  const readWithWatchdog = async (): Promise<ReadableStreamReadResult<Uint8Array>> => {
    let timer: ReturnType<typeof setTimeout> | undefined;
    try {
      return await Promise.race([
        reader.read(),
        new Promise<never>((_, reject) => {
          timer = setTimeout(() => {
            void reader.cancel().catch(() => {
              /* the stream is already unusable if cancel fails */
            });
            reject(
              new TajpoError(
                "streamStalled",
                "The model stopped sending text. The connection stalled — try again.",
              ),
            );
          }, streamStallTimeout.ms);
        }),
      ]);
    } finally {
      if (timer !== undefined) clearTimeout(timer);
    }
  };

  while (true) {
    const { value, done } = await readWithWatchdog();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });
    processBuffer(false);
    if (sawDone) break;
  }
  if (!sawDone) processBuffer(true);

  const finalRaw = result.trim();
  if (!finalRaw) throw new TajpoError("emptyResponse", "The model returned no text.");
  // Guarantee custom instructions ("never use the word X", "no exclamation",
  // "replace X with Y") on the remote path too — the model cannot be trusted
  // to obey them, so they are enforced as a post-processor.
  const final = customInstructions.trim() ? applyCustomInstructions(finalRaw, customInstructions) : finalRaw;
  if (!final) throw new TajpoError("emptyResponse", "The model returned no usable text.");
  const output: RewriteResultLike = { text: final };
  if (usage && usage.promptTokens !== undefined && usage.completionTokens !== undefined) {
    output.usage = { promptTokens: usage.promptTokens, completionTokens: usage.completionTokens };
  }
  if (finishReason && finishReason !== "stop") output.finishReason = finishReason;
  return output;
}

function parseAPIError(body: string, status: number): string {
  try {
    const parsed = JSON.parse(body) as { error?: { message?: string } };
    if (parsed.error?.message) return parsed.error.message;
  } catch {
    /* keep fallback */
  }
  return `HTTP ${status}`;
}

export async function testConnection(options: {
  provider: LLMProvider;
  baseURL: string;
  model: string;
  apiKey: string;
  authStyle: LLMAuthStyle;
  apiVersion?: string;
}): Promise<{ ok: boolean; message: string }> {
  if (options.provider === "demo") {
    return { ok: true, message: "Demo engine is ready. Nothing leaves this browser." };
  }
  const trimmed = (options.baseURL || (options.provider === "openAI" ? "https://api.openai.com/v1" : "http://127.0.0.1:11434/v1"))
    .trim()
    .replace(/\/+$/, "");
  if (!trimmed) return { ok: false, message: "Add a base URL first." };
  try {
    const headers: Record<string, string> = {};
    if (options.authStyle === "bearer" && options.apiKey) headers.Authorization = `Bearer ${options.apiKey}`;
    if (options.authStyle === "apiKeyHeader" && options.apiKey) headers["api-key"] = options.apiKey;
    // Azure OpenAI has no /models at the resource root — ping its models
    // endpoint with the configured api-version instead.
    const pingURL = options.apiVersion?.trim()
      ? `${trimmed}/openai/models?api-version=${encodeURIComponent(options.apiVersion.trim())}`
      : `${trimmed}/models`;
    const response = await fetch(pingURL, { headers });
    if (response.status === 429) return { ok: false, message: "Rate limited. Wait and retry." };
    if (!response.ok) return { ok: false, message: `Could not reach ${trimmed} (HTTP ${response.status}).` };
    return { ok: true, message: `Connected to ${trimmed}. Model ${options.model || "unspecified"} is ready to try.` };
  } catch (error) {
    // Never leak the API key or header material through network error messages.
    const raw = error instanceof Error ? error.message : "";
    const safe = options.apiKey ? raw.split(options.apiKey).join("[redacted]") : raw;
    return { ok: false, message: safe || "The local or remote server did not respond." };
  }
}
