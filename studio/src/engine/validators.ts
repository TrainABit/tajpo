import { maximumCharacters } from "./types";

export class TajpoError extends Error {
  constructor(
    public readonly code: string,
    message: string,
  ) {
    super(message);
    this.name = "TajpoError";
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

export function tokenCostLabel(model: string, promptTokens: number, completionTokens: number): string {
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
