import { antiSlop, type RewriteAction, type RewriteLength, type RewriteTone, type WritingPreset } from "./types";

export function systemPrompt(
  action: RewriteAction,
  tone: RewriteTone,
  preset?: WritingPreset | null,
  customInstructions?: string | null,
  length: RewriteLength = "same",
): string {
  const task = {
    correct:
      "Correct only grammar, spelling, and punctuation. Do not change meaning, tone, structure, or word choice unless required for correctness.",
    improve: "Improve clarity and flow while preserving meaning and voice.",
    rewrite: "Rewrite naturally while preserving meaning and all facts.",
    shorten: "Make it shorter without losing key information.",
    changeTone: `Rewrite in a ${tone} tone while preserving meaning and facts. The requested tone wins if any other style note conflicts.`,
    expand: "Expand slightly with one or two clarifying sentences. Do not invent facts, numbers, or names.",
    simplify: "Rewrite with shorter, more common words. Keep meaning and facts.",
    bullets:
      "Turn the text into a tight bullet list. Keep every fact. Do not add a heading unless the source already has one.",
    continueWriting:
      "Write the next one or two sentences in the same voice. Do not repeat the source. Do not add facts that are not implied.",
  }[action];

  const presetClause = preset
    ? action === "changeTone"
      ? `Style notes (must not override the requested ${tone} tone): ${preset.systemPrompt}`
      : preset.systemPrompt
    : null;

  const custom = customInstructions?.trim();
  const customClause = custom ? `Extra instructions from the user: ${custom}` : null;
  const lengthClause =
    length === "shorter"
      ? "Make the result shorter than the source without losing key facts."
      : length === "longer"
        ? "Make the result a little longer with one clarifying sentence. Do not invent facts."
        : null;

  return [task, presetClause, customClause, lengthClause, antiSlop, "Preserve the original language. Do not add facts. Return only the final text without quotes or commentary."]
    .filter(Boolean)
    .join(" ");
}

export function temperatureFor(action: RewriteAction): number {
  if (action === "correct" || action === "bullets") return 0;
  if (action === "improve" || action === "simplify" || action === "shorten") return 0.3;
  return 0.5;
}
