import lexiconJson from "../../../Sources/TajpoCore/Resources/demo-lexicon.json";
import { applyCustomInstructions } from "./style";
import type { DemoLexicon, RewriteAction, RewriteLength, RewriteTone, WritingPreset } from "./types";

export const demoLexicon = lexiconJson as DemoLexicon;

export class DemoRewriter {
  constructor(private readonly lexicon: DemoLexicon = demoLexicon) {}

  rewrite(
    text: string,
    action: RewriteAction,
    tone: RewriteTone,
    extras: { length?: RewriteLength; preset?: WritingPreset | null; customInstructions?: string } = {},
  ): string {
    const source = text.trim();
    if (!source) return source;
    let output: string;
    switch (action) {
      case "correct":
        output = this.correct(source);
        break;
      case "improve":
        output = this.improve(this.correct(source));
        break;
      case "rewrite":
        output = this.rewriteNatural(this.improve(this.correct(source)));
        break;
      case "shorten":
        output = this.shorten(this.correct(source));
        break;
      case "changeTone":
        output = this.applyTone(this.correct(source), tone);
        break;
      case "expand":
        output = this.expand(this.correct(source));
        break;
      case "simplify":
        output = this.simplify(this.correct(source));
        break;
      case "bullets":
        output = this.bullets(this.correct(source));
        break;
      case "continueWriting":
        output = this.continueWriting(this.correct(source));
        break;
    }
    output = this.applyPreset(output, extras.preset);
    output = this.applyLength(output, extras.length ?? "same");
    output = applyCustomInstructions(output, extras.customInstructions ?? "");
    return action === "bullets" ? this.tidy(output) : this.capitalizeSentences(this.tidy(output));
  }

  applyPreset(text: string, preset?: WritingPreset | null): string {
    if (!preset) return text;
    const name = preset.name.toLowerCase();
    const prompt = preset.systemPrompt.toLowerCase();
    if (name === "concise" || prompt.includes("short sentences") || prompt.includes("cut anything")) {
      return this.shorten(text);
    }
    if (name === "professional" || prompt.includes("professional tone")) {
      return this.applyTone(text, "professional");
    }
    if (name === "casual" || prompt.includes("relaxed")) {
      return this.applyTone(text, "casual");
    }
    if (name === "warm" || prompt.includes("warmth")) {
      return this.applyTone(text, "friendly");
    }
    return text;
  }

  applyLength(text: string, length: RewriteLength): string {
    if (length === "shorter") return this.shorten(text);
    if (length === "longer") return this.expand(text);
    return text;
  }

  correct(text: string): string {
    let result = this.replaceMapped(text, this.lexicon.typos);
    result = this.replaceMapped(result, this.lexicon.casualSlang);
    result = this.normalizeSpaces(result);
    result = result.replace(/\bi\b/g, "I");
    result = result.replace(/\b(brief|document|note|draft) need\b/gi, (_, word: string) => `${word} needs`);
    return this.capitalizeSentences(result);
  }

  improve(text: string): string {
    let result = this.removeListed(text, this.lexicon.filler);
    result = this.replaceMapped(result, this.lexicon.wordy);
    return this.normalizeSpaces(result);
  }

  shorten(text: string): string {
    let result = this.improve(text);
    result = result.replace(/\s*\([^)]*\)/g, "");
    result = result.replace(/(?:, I guess|, I suppose|, you know| I guess| I suppose)$/i, "");
    return this.normalizeSpaces(result);
  }

  applyTone(text: string, tone: RewriteTone): string {
    if (tone === "professional") {
      let result = this.replaceMapped(text, this.lexicon.casualSlang);
      result = this.replaceMapped(result, this.lexicon.expandContractions);
      return this.capitalizeSentences(result);
    }
    if (tone === "casual") return this.replaceMapped(text, this.lexicon.addContractions);
    if (tone === "friendly") {
      let result = this.replaceMapped(text, this.lexicon.addContractions);
      result = this.removeListed(result, ["unfortunately", "regrettably"]);
      return result;
    }
    let result = this.removeListed(text, this.lexicon.hedges);
    result = this.removeListed(result, this.lexicon.filler);
    return this.normalizeSpaces(result);
  }

  expand(text: string): string {
    const cleaned = text.trim();
    if (cleaned.includes("That is the point to keep in view.")) return cleaned;
    const addition = "That is the point to keep in view.";
    return /[.!?]$/.test(cleaned) ? `${cleaned} ${addition}` : `${cleaned}. ${addition}`;
  }

  simplify(text: string): string {
    return this.replaceMapped(text, this.lexicon.simplify);
  }

  bullets(text: string): string {
    const sentences = this.splitSentences(text);
    if (sentences.length >= 2) return sentences.map((item) => `- ${item}`).join("\n");
    const parts = text
      .split(/[,;]/)
      .map((item) => item.trim())
      .filter(Boolean);
    if (parts.length >= 2) {
      return parts.map((item) => `- ${this.capitalizeSentences(item.replace(/[.;]$/, ""))}`).join("\n");
    }
    return `- ${text.trim()}`;
  }

  continueWriting(text: string): string {
    const cleaned = text.trim();
    const last = this.splitSentences(cleaned).at(-1) ?? cleaned;
    if (last.endsWith("?")) {
      return `${cleaned} The short answer is yes, for the reasons already stated.`;
    }
    const snippet = last
      .replace(/[^\w\s]/g, "")
      .trim()
      .split(/\s+/)
      .slice(-6)
      .join(" ");
    if (!snippet) return `${cleaned} The next step is to act on that.`;
    const lowered = snippet.charAt(0).toLowerCase() + snippet.slice(1);
    return `${cleaned} The next step is to follow through on ${lowered}.`;
  }

  rewriteNatural(text: string): string {
    const sentences = this.splitSentences(text);
    if (sentences.length < 2) return text.endsWith(".") ? text : `${text}.`;
    const [first, ...rest] = sentences;
    return [...rest, first].join(" ");
  }

  private replaceMapped(text: string, map: Record<string, string>): string {
    return Object.entries(map)
      .sort((a, b) => b[0].length - a[0].length)
      .reduce((current, [key, value]) => this.replacePhrase(current, key, value), text);
  }

  private removeListed(text: string, phrases: string[]): string {
    const next = [...phrases]
      .sort((a, b) => b.length - a.length)
      .reduce((current, phrase) => this.replacePhrase(current, phrase, ""), text);
    return this.normalizeSpaces(next);
  }

  private replacePhrase(text: string, key: string, value: string): string {
    const escaped = key.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    const regex = new RegExp(`\\b${escaped}\\b`, "gi");
    return text.replace(regex, (sample) => (value === "" ? "" : preserveCase(sample, value)));
  }

  private normalizeSpaces(text: string): string {
    return text
      .replace(/[ \t]+/g, " ")
      .replace(/ *\n+ */g, "\n")
      .replace(/ +([,.;:!?])/g, "$1")
      .replace(/([.!?])([A-Za-z])/g, "$1 $2")
      .trim();
  }

  private capitalizeSentences(text: string): string {
    let capitalize = true;
    let result = "";
    for (const character of text) {
      if (capitalize && /[A-Za-z]/.test(character)) {
        result += character.toUpperCase();
        capitalize = false;
      } else {
        result += character;
        if (".!?".includes(character)) capitalize = true;
      }
    }
    return result;
  }

  private splitSentences(text: string): string[] {
    return text
      .split(/(?<=[.!?])\s+/)
      .map((item) => item.trim())
      .filter(Boolean);
  }

  private tidy(text: string): string {
    return this.normalizeSpaces(text).replace(" ,", ",").replace(" .", ".");
  }
}

function preserveCase(sample: string, replacement: string): string {
  if (sample.length > 1 && sample === sample.toUpperCase()) return replacement.toUpperCase();
  if (sample[0] && sample[0] === sample[0].toUpperCase()) {
    return replacement.charAt(0).toUpperCase() + replacement.slice(1);
  }
  return replacement;
}

export async function streamDemo(
  text: string,
  action: RewriteAction,
  tone: RewriteTone,
  onPartial: (value: string) => void,
  signal?: AbortSignal,
  delayMs = 8,
  extras: { length?: RewriteLength; preset?: WritingPreset | null; customInstructions?: string } = {},
): Promise<RewriteResultLike> {
  const output = new DemoRewriter().rewrite(text, action, tone, extras);
  let partial = "";
  for (const character of output) {
    if (signal?.aborted) throw new DOMException("The rewrite was cancelled.", "AbortError");
    partial += character;
    onPartial(partial);
    if (delayMs > 0) await sleep(delayMs);
  }
  return {
    text: output,
    usage: {
      promptTokens: text.split(/\s+/).filter(Boolean).length,
      completionTokens: output.split(/\s+/).filter(Boolean).length,
    },
  };
}

export interface RewriteResultLike {
  text: string;
  usage?: { promptTokens: number; completionTokens: number };
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
