export const rewriteActions = [
  "correct",
  "improve",
  "rewrite",
  "shorten",
  "changeTone",
  "expand",
  "simplify",
  "bullets",
  "continueWriting",
] as const;

export type RewriteAction = (typeof rewriteActions)[number];

export const rewriteTones = ["professional", "friendly", "confident", "casual"] as const;
export type RewriteTone = (typeof rewriteTones)[number];

export type LLMProvider = "demo" | "openAI" | "localCompatible";
export type LLMAuthStyle = "bearer" | "apiKeyHeader" | "none";

export interface WritingPreset {
  id: string;
  name: string;
  systemPrompt: string;
}

export interface TokenUsage {
  promptTokens: number;
  completionTokens: number;
}

export interface RewriteResult {
  text: string;
  usage?: TokenUsage;
}

export interface DemoLexicon {
  typos: Record<string, string>;
  filler: string[];
  hedges: string[];
  wordy: Record<string, string>;
  simplify: Record<string, string>;
  expandContractions: Record<string, string>;
  addContractions: Record<string, string>;
  casualSlang: Record<string, string>;
}

export const actionMeta: Record<RewriteAction, { title: string; subtitle: string; digit: string }> = {
  correct: { title: "Correct", subtitle: "Grammar and spelling only", digit: "1" },
  improve: { title: "Improve", subtitle: "Clearer, same meaning", digit: "2" },
  rewrite: { title: "Rewrite", subtitle: "Fresh wording", digit: "3" },
  shorten: { title: "Shorten", subtitle: "Keep the point, cut words", digit: "4" },
  changeTone: { title: "Tone", subtitle: "Same facts, new voice", digit: "5" },
  expand: { title: "Expand", subtitle: "Add a little room", digit: "6" },
  simplify: { title: "Simplify", subtitle: "Shorter words", digit: "7" },
  bullets: { title: "Bullets", subtitle: "Turn it into a list", digit: "8" },
  continueWriting: { title: "Continue", subtitle: "Write the next beat", digit: "9" },
};

export const defaultPresets: WritingPreset[] = [
  {
    id: "professional",
    name: "Professional",
    systemPrompt: "Use a clear, direct, professional tone. Prefer simple words. Avoid corporate jargon.",
  },
  {
    id: "casual",
    name: "Casual",
    systemPrompt:
      "Sound relaxed and human. Use natural contractions where the language supports them. Do not sound performative.",
  },
  {
    id: "concise",
    name: "Concise",
    systemPrompt: "Prefer short sentences and concrete verbs. Cut anything that does not carry information.",
  },
  {
    id: "warm",
    name: "Warm",
    systemPrompt: "Be considerate and plain. Keep warmth in the voice without cheerleading or exclamation marks.",
  },
];

export const hosts = ["notes", "mail", "slack"] as const;
export type HostId = (typeof hosts)[number];

export const hostDocuments: Record<HostId, { title: string; subtitle: string; body: string }> = {
  notes: {
    title: "Notes",
    subtitle: "Draft",
    body: "tajpo make this sentance better so i can really just send it to the team today.",
  },
  mail: {
    title: "Mail",
    subtitle: "To design",
    body: "i wanted to reach out in order to utilize this time and recieve feedback. maybe we can definately meet tomorrow.",
  },
  slack: {
    title: "Slack",
    subtitle: "#writing",
    body: "hey can we actually just ship the rewrite panel today i think its ready and it would be usefull",
  },
};

export const maximumCharacters = 100_000;
export const antiSlop =
  "Avoid filler, canned openings, inflated language, fake enthusiasm, generic transitions, repetitive conclusions, and AI-sounding phrases. Do not use em dashes. Keep the author's voice and level of formality.";
