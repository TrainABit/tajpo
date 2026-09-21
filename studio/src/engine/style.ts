import type { HistoryEntry, RewriteAction } from "./types";

// Only treat a match as a banned word when the instruction explicitly names a
// word — either via "the word X" or a quoted "X". Bare phrasing such as
// "avoid long sentences" must NOT delete the word "long" from the document.
const bannedWordPattern =
  /(?:never use|don't use|do not use|avoid)\s+(?:the\s+word\s+|words?\s+like\s+)["“'`]?([A-Za-z][A-Za-z'-]*)["”'`]?|(?:never use|don't use|do not use|avoid)\s+["“]([A-Za-z][A-Za-z'-]*)["”]/gi;

// "replace X with Y" (optionally "the word X") — case-insensitive whole-word
// substitution. Matched separately from the banned-word pattern so phrasing
// like "never use the word X" is never misread as a replacement rule.
const replaceRulePattern =
  /replace\s+(?:the\s+word\s+)?["“'`]?([A-Za-z][A-Za-z'-]*)["”'`]?\s+with\s+["“'`]?([A-Za-z][A-Za-z'-]*)["”'`]?/gi;

export function applyCustomInstructions(text: string, instructions: string): string {
  let result = text;
  for (const match of instructions.matchAll(bannedWordPattern)) {
    const word = match[1] ?? match[2];
    if (!word) continue;
    const escaped = word.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    result = result.replace(new RegExp(`\\b${escaped}\\b`, "gi"), "").replace(/[ \t]{2,}/g, " ");
  }
  for (const match of instructions.matchAll(replaceRulePattern)) {
    const from = match[1];
    const to = match[2];
    if (!from || !to) continue;
    const escaped = from.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    result = result.replace(new RegExp(`\\b${escaped}\\b`, "gi"), to);
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
  const left = original ? original.split(/(\s+)/) : [];
  const right = next ? next.split(/(\s+)/) : [];
  // O(1) membership lookups — linear Array.includes scans here are O(n²)
  // and stall the UI on long documents.
  const leftSet = new Set(left);
  const rightSet = new Set(right);
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
    if (j < right.length && !leftSet.has(right[j])) {
      tokens.push({ text: right[j], kind: "add" });
      j += 1;
      continue;
    }
    if (i < left.length && !rightSet.has(left[i])) {
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
