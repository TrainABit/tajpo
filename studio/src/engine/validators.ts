import { maximumCharacters } from "./types";

export class TajpoError extends Error {
  /** Suggested wait before retrying, parsed from a 429 Retry-After header. */
  public readonly retryAfterMs?: number;

  constructor(
    public readonly code: string,
    message: string,
    options?: { retryAfterMs?: number },
  ) {
    super(message);
    this.name = "TajpoError";
    if (options?.retryAfterMs !== undefined) this.retryAfterMs = options.retryAfterMs;
  }
}

export function validateSelection(text: string): string {
  const trimmed = text.replace(/^\s+|\s+$/g, "");
  if (!trimmed) {
    throw new TajpoError("noSelection", "No selected text found. Select text and try again.");
  }
  if (text.length > maximumCharacters) {
    throw new TajpoError("textTooLarge", "The selection is too large. Select fewer than 100,000 characters.");
  }
  return text;
}

export function validateAPIKey(key: string): string {
  const trimmed = key.trim();
  if (!trimmed) {
    throw new TajpoError("missingAPIKey", "Add your API key in Settings, or switch to the on-device demo.");
  }
  return trimmed;
}

export function chatCompletionsURL(baseURL: string, model: string, apiVersion = ""): string {
  const trimmed = baseURL.trim().replace(/\/+$/, "");
  if (!trimmed) {
    throw new TajpoError(
      "invalidEndpoint",
      "The API base URL is invalid. Use a full URL such as https://api.openai.com/v1.",
    );
  }
  if (apiVersion.trim()) {
    return `${trimmed}/openai/deployments/${encodeURIComponent(model)}/chat/completions?api-version=${encodeURIComponent(apiVersion)}`;
  }
  return `${trimmed}/chat/completions`;
}

/**
 * Validates text that is about to be sent to a paid remote API. Applies the
 * same selection rules as the demo path so oversized selections never go
 * straight to the network. Returns the text unchanged.
 */
export function validateRemoteInput(text: string): string {
  return validateSelection(text);
}

/**
 * Parses a Retry-After header value (integer seconds or HTTP-date) into
 * milliseconds from now. Returns undefined when absent or unparseable.
 */
export function parseRetryAfter(header: string | null, now = Date.now()): number | undefined {
  if (!header) return undefined;
  const trimmed = header.trim();
  if (!trimmed) return undefined;
  if (/^\d+$/.test(trimmed)) return Number(trimmed) * 1000;
  const date = Date.parse(trimmed);
  if (!Number.isNaN(date)) return Math.max(0, date - now);
  return undefined;
}

export function tokenCostLabel(
  model: string,
  promptTokens?: number,
  completionTokens?: number,
): string {
  // Only label when both sides of the usage are known — zero-filling a missing
  // field would produce misleading cost labels.
  if (promptTokens === undefined || completionTokens === undefined) return "";
  const total = promptTokens + completionTokens;
  const rates: Record<string, { input: number; output: number }> = {
    "gpt-4o-mini": { input: 0.15, output: 0.6 },
    "gpt-4o": { input: 2.5, output: 10 },
    "gpt-4.1-mini": { input: 0.4, output: 1.6 },
    "gpt-4.1": { input: 2, output: 8 },
  };
  const rate = rates[model];
  if (!rate) return `${total} tokens`;
  const usd = (promptTokens * rate.input + completionTokens * rate.output) / 1_000_000;
  return `${total} tokens · about $${usd.toFixed(4)}`;
}

/** Rough client-side token estimate (~4 characters per token) for when the
 * server omits usage data. Minimum of 1 for non-empty text. */
export function estimateTokenCount(text: string): number {
  if (!text) return 0;
  return Math.max(1, Math.ceil(text.length / 4));
}

/** Short human-facing label for a streaming finish_reason. Returns "" for a
 * normal stop or an absent reason so callers can render nothing. */
export function finishReasonLabel(finishReason?: string): string {
  if (!finishReason || finishReason === "stop") return "";
  if (finishReason === "length") return "Output truncated (length limit)";
  if (finishReason === "content_filter") return "Output blocked by content filter";
  return `Output ended early (${finishReason})`;
}
