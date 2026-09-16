import type { HistoryEntry, RewriteAction } from "./types";

export function applyCustomInstructions(text: string, instructions: string): string {
  let result = text;
  const neverWord = instructions.match(
    /(?:never use|don't use|do not use|avoid)(?: the word)? ["“]?([A-Za-z][A-Za-z'-]*)["”]?/i,
  );
  if (neverWord?.[1]) {
    const escaped = neverWord[1].replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    result = result.replace(new RegExp(`\\b${escaped}\\b`, "gi"), "").replace(/[ \t]{2,}/g, " ");
  }
  if (/no exclamation/i.test(instructions)) {
    result = result.replace(/!+/g, ".");
  }
  return result.replace(/ +([,.;:!?])/g, "$1").replace(/[ \t]+/g, " ").trim();
}

export interface Replacement {
  host: string;
  start: number;
  end: number;
  original: string;
  rewritten: string;
}

export function applyReplacement(
  body: string,
  start: number,
  end: number,
  rewritten: string,
): { next: string; entry: Omit<Replacement, "host"> } {
  return {
    next: body.slice(0, start) + rewritten + body.slice(end),
    entry: {
      start,
      end: start + rewritten.length,
      original: body.slice(start, end),
      rewritten,
    },
  };
}

export function undoReplacement(body: string, entry: Omit<Replacement, "host">): string {
  return body.slice(0, entry.start) + entry.original + body.slice(entry.end);
}

export function redoReplacement(body: string, entry: Omit<Replacement, "host">): string {
  return body.slice(0, entry.start) + entry.rewritten + body.slice(entry.start + entry.original.length);
}

export function filterHistory(
  entries: HistoryEntry[],
  query: string,
  action: RewriteAction | "all",
): HistoryEntry[] {
  const needle = query.trim().toLowerCase();
  return entries.filter((entry) => {
    if (action !== "all" && entry.action !== action) return false;
    if (!needle) return true;
    return `${entry.original} ${entry.result} ${entry.action} ${entry.tone}`.toLowerCase().includes(needle);
  });
}

export type DiffKind = "same" | "add" | "del";
export interface DiffToken {
  text: string;
  kind: DiffKind;
}

export function wordDiff(original: string, next: string): DiffToken[] {
  const left = original.split(/(\s+)/);
  const right = next.split(/(\s+)/);
  const tokens: DiffToken[] = [];
  let i = 0;
  let j = 0;
  while (i < left.length || j < right.length) {
    if (i < left.length && j < right.length && left[i] === right[j]) {
      tokens.push({ text: left[i], kind: "same" });
      i += 1;
      j += 1;
      continue;
    }
    if (j < right.length && !left.includes(right[j])) {
      tokens.push({ text: right[j], kind: "add" });
      j += 1;
      continue;
    }
    if (i < left.length && !right.includes(left[i])) {
      tokens.push({ text: left[i], kind: "del" });
      i += 1;
      continue;
    }
    if (i < left.length) {
      tokens.push({ text: left[i], kind: "del" });
      i += 1;
    }
    if (j < right.length) {
      tokens.push({ text: right[j], kind: "add" });
      j += 1;
    }
  }
  return tokens;
}

export function countWords(text: string): number {
  return text.trim() ? text.trim().split(/\s+/).length : 0;
}
