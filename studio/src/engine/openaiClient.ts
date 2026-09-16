import { systemPrompt, temperatureFor } from "./prompts";
import type { LLMAuthStyle, LLMProvider, RewriteAction, RewriteLength, RewriteTone, WritingPreset } from "./types";
import { chatCompletionsURL, TajpoError } from "./validators";
import type { RewriteResultLike } from "./demoRewriter";

export interface RemoteClientOptions {
  baseURL: string;
  model: string;
  apiKey: string;
  authStyle: "bearer" | "apiKeyHeader" | "none";
  apiVersion?: string;
}

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
    throw new TajpoError("rateLimited", "The model rate limit was reached. Wait a moment and retry.");
  }
  if (!response.ok || !response.body) {
    const body = await response.text();
    throw new TajpoError("api", parseAPIError(body, response.status));
  }

  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  let result = "";
  let usage: RewriteResultLike["usage"];

  while (true) {
    const { value, done } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });
    const lines = buffer.split("\n");
    buffer = lines.pop() ?? "";
    for (const line of lines) {
      const trimmed = line.trim();
      if (!trimmed.startsWith("data: ")) continue;
      const payload = trimmed.slice(6);
      if (payload === "[DONE]") {
        if (!result.trim()) throw new TajpoError("emptyResponse", "The model returned no text.");
        return { text: result.trim(), usage };
      }
      try {
        const event = JSON.parse(payload) as {
          choices?: { delta?: { content?: string } }[];
          error?: { message?: string };
          usage?: { prompt_tokens?: number; completion_tokens?: number };
        };
        if (event.error?.message) throw new TajpoError("api", event.error.message);
        if (event.usage) {
          usage = {
            promptTokens: event.usage.prompt_tokens ?? 0,
            completionTokens: event.usage.completion_tokens ?? 0,
          };
        }
        const delta = event.choices?.[0]?.delta?.content;
        if (delta) {
          result += delta;
          onPartial(result);
        }
      } catch (error) {
        if (error instanceof TajpoError) throw error;
      }
    }
  }

  const final = result.trim();
  if (!final) throw new TajpoError("emptyResponse", "The model returned no text.");
  return { text: final, usage };
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
    const response = await fetch(`${trimmed}/models`, { headers });
    if (response.status === 429) return { ok: false, message: "Rate limited. Wait and retry." };
    if (!response.ok) return { ok: false, message: `Could not reach ${trimmed} (HTTP ${response.status}).` };
    return { ok: true, message: `Connected to ${trimmed}. Model ${options.model || "unspecified"} is ready to try.` };
  } catch (error) {
    return { ok: false, message: error instanceof Error ? error.message : "The local or remote server did not respond." };
  }
}
