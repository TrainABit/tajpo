import {
  createContext,
  useContext,
  useEffect,
  useMemo,
  useReducer,
  useRef,
  useState,
  type Dispatch,
  type ReactNode,
} from "react";
import {
  applyReplacement,
  defaultPresets,
  estimateTokenCount,
  filterHistory,
  finishReasonLabel,
  hostDocuments,
  redoReplacement,
  streamDemo,
  streamRemote,
  testConnection,
  tokenCostLabel,
  undoReplacement,
  validateAPIKey,
  validateSelection,
  type HistoryEntry,
  type HostId,
  type LLMAuthStyle,
  type LLMProvider,
  type Replacement,
  type RewriteAction,
  type RewriteLength,
  type RewriteTone,
  type StudioTheme,
  type WritingPreset,
} from "../engine";

export type { HistoryEntry };

export interface StudioSettings {
  provider: LLMProvider;
  model: string;
  baseURL: string;
  apiKey: string;
  authStyle: LLMAuthStyle;
  apiVersion: string;
  customInstructions: string;
  historyEnabled: boolean;
  theme: StudioTheme;
  shortcut: { alt: boolean; shift: boolean; meta: boolean; ctrl: boolean; key: string };
}

export interface Toast {
  message: string;
  kind: "ok" | "error";
}

export interface StudioState {
  host: HostId;
  documents: Record<HostId, string>;
  selection: { start: number; end: number } | null;
  original: string;
  preview: string;
  action: RewriteAction;
  tone: RewriteTone;
  length: RewriteLength;
  showDiff: boolean;
  status: string;
  isWorking: boolean;
  isError: boolean;
  usageLabel: string;
  panelOpen: boolean;
  menuOpen: boolean;
  settingsOpen: boolean;
  historyOpen: boolean;
  onboardingOpen: boolean;
  onboardingStep: number;
  settings: StudioSettings;
  presets: WritingPreset[];
  selectedPresetId: string;
  history: HistoryEntry[];
  historyQuery: string;
  historyAction: RewriteAction | "all";
  historyHost: "all" | HostId;
  lastDeletedHistory: HistoryEntry | null;
  lastDeletedHistoryIndex: number;
  undoStack: Replacement[];
  redoStack: Replacement[];
  toast: Toast | null;
  clock: string;
}

type Action =
  | { type: "hydrate"; state: Partial<StudioState> }
  | { type: "set-host"; host: HostId }
  | { type: "set-document"; host: HostId; body: string }
  | { type: "set-selection"; selection: { start: number; end: number } | null }
  | { type: "set-action"; action: RewriteAction }
  | { type: "set-tone"; tone: RewriteTone }
  | { type: "set-length"; length: RewriteLength }
  | { type: "toggle-diff" }
  | { type: "open-panel"; original: string; error?: string }
  | { type: "close-panel" }
  | { type: "toggle-menu"; open?: boolean }
  | { type: "toggle-settings"; open?: boolean }
  | { type: "toggle-history"; open?: boolean }
  | { type: "set-onboarding"; open: boolean; step?: number }
  | { type: "working"; original?: string }
  | { type: "partial"; preview: string }
  | { type: "ready"; preview: string; usageLabel: string }
  | { type: "fail"; status: string }
  | { type: "status"; status: string; isError?: boolean }
  | { type: "apply"; start: number; end: number; rewritten: string }
  | { type: "undo" }
  | { type: "redo" }
  | { type: "record-history"; entry: HistoryEntry }
  | { type: "clear-history" }
  | { type: "restore-history"; entry: HistoryEntry }
  | { type: "history-query"; query: string }
  | { type: "history-action"; action: RewriteAction | "all" }
  | { type: "history-host"; host: "all" | HostId }
  | { type: "delete-history-entry"; id: string }
  | { type: "undo-delete-history" }
  | { type: "update-settings"; settings: Partial<StudioSettings> }
  | { type: "set-presets"; presets: WritingPreset[]; selectedPresetId?: string }
  | { type: "toast"; toast: Toast | null }
  | { type: "tick"; clock: string }
  | { type: "idle" };

const storageKey = "tajpo.studio.v2";
const legacyStorageKey = "tajpo.studio.v1";
const onboardedKey = "tajpo.studio.onboarded";
const storageVersion = 2;
const undoLimit = 50;
const historyLimit = 40;
const historyByteBudget = 1024 * 1024; // 1 MiB of UTF-8 across the history list
const stackByteBudget = 256 * 1024; // 256 KiB of UTF-8 per undo/redo stack
const persistThrottleMs = 750; // max write frequency while a stream is running

const defaultSettings: StudioSettings = {
  provider: "demo",
  model: "tajpo-demo",
  baseURL: import.meta.env.VITE_OPENAI_BASE_URL ?? "",
  apiKey: import.meta.env.VITE_OPENAI_API_KEY ?? "",
  authStyle: "none",
  apiVersion: "",
  customInstructions: "",
  historyEnabled: true,
  theme: "dark",
  shortcut: { alt: true, shift: true, meta: false, ctrl: false, key: "t" },
};

function emptyDocuments(): Record<HostId, string> {
  return {
    notes: hostDocuments.notes.body,
    mail: hostDocuments.mail.body,
    slack: hostDocuments.slack.body,
    docs: hostDocuments.docs.body,
  };
}

const utf8 = new TextEncoder();

function utf8Bytes(value: unknown): number {
  return utf8.encode(JSON.stringify(value)).length;
}

/** Enforce the history byte budget. The list is newest-first, so entries past
 * the budget are the oldest ones and get evicted. A single entry larger than
 * the whole budget is skipped rather than truncated; the caller surfaces that
 * with a toast via `skippedOversized`. */
export function budgetHistory(history: HistoryEntry[]): { history: HistoryEntry[]; skippedOversized: boolean } {
  const kept: HistoryEntry[] = [];
  let total = 0;
  let skippedOversized = false;
  for (const entry of history) {
    const bytes = utf8Bytes(entry);
    if (bytes > historyByteBudget) {
      skippedOversized = true;
      continue;
    }
    if (kept.length >= historyLimit || total + bytes > historyByteBudget) break;
    total += bytes;
    kept.push(entry);
  }
  return { history: kept, skippedOversized };
}

/** Enforce the undo/redo byte budget. The stack is oldest-first, so the
 * oldest entries are evicted while the newest ones are always kept. Count is
 * capped separately by the `undoLimit` slices at the call sites. */
export function budgetStack(stack: Replacement[]): Replacement[] {
  let total = 0;
  for (let i = stack.length - 1; i >= 0; i -= 1) {
    total += utf8Bytes(stack[i]);
    if (total > stackByteBudget) return stack.slice(i + 1);
  }
  return stack;
}

/** Whether a persistence write should happen now: during an active stream,
 * partial tokens arrive far faster than storage should be hit, so writes are
 * throttled; the moment the stream ends (or the panel closes) the write is
 * flushed immediately. */
export function shouldWritePersist(isWorking: boolean, lastWriteAt: number, now: number): boolean {
  return !isWorking || now - lastWriteAt >= persistThrottleMs;
}

export function createInitialState(): StudioState {
  return {
    host: "notes",
    documents: emptyDocuments(),
    selection: null,
    original: "",
    preview: "",
    action: "correct",
    tone: "professional",
    length: "same",
    showDiff: false,
    status: "Ready",
    isWorking: false,
    isError: false,
    usageLabel: "",
    panelOpen: false,
    menuOpen: false,
    settingsOpen: false,
    historyOpen: false,
    onboardingOpen: true,
    onboardingStep: 0,
    settings: defaultSettings,
    presets: defaultPresets,
    selectedPresetId: defaultPresets[0].id,
    history: [],
    historyQuery: "",
    historyAction: "all",
    historyHost: "all",
    lastDeletedHistory: null,
    lastDeletedHistoryIndex: -1,
    undoStack: [],
    redoStack: [],
    toast: null,
    clock: "9:41",
  };
}

export function reduceStudio(state: StudioState, action: Action): StudioState {
  switch (action.type) {
    case "hydrate":
      return {
        ...state,
        ...action.state,
        isWorking: false,
        menuOpen: false,
        panelOpen: false,
        toast: null,
        lastDeletedHistory: null,
        lastDeletedHistoryIndex: -1,
        documents: { ...emptyDocuments(), ...action.state.documents },
      };
    case "set-host":
      return { ...state, host: action.host, selection: null };
    case "set-document":
      return { ...state, documents: { ...state.documents, [action.host]: action.body } };
    case "set-selection":
      return { ...state, selection: action.selection };
    case "set-action":
      return { ...state, action: action.action };
    case "set-tone":
      return { ...state, tone: action.tone };
    case "set-length":
      return { ...state, length: action.length };
    case "toggle-diff":
      return { ...state, showDiff: !state.showDiff };
    case "open-panel":
      return {
        ...state,
        panelOpen: true,
        menuOpen: false,
        original: action.original,
        preview: "",
        usageLabel: "",
        isWorking: false,
        isError: Boolean(action.error),
        status: action.error ?? "Choose an action",
      };
    case "close-panel":
      return { ...state, panelOpen: false, isWorking: false };
    case "toggle-menu":
      return { ...state, menuOpen: action.open ?? !state.menuOpen };
    case "toggle-settings":
      return { ...state, settingsOpen: action.open ?? !state.settingsOpen, menuOpen: false };
    case "toggle-history":
      return { ...state, historyOpen: action.open ?? !state.historyOpen, menuOpen: false };
    case "set-onboarding":
      return { ...state, onboardingOpen: action.open, onboardingStep: action.step ?? state.onboardingStep };
    case "working":
      return {
        ...state,
        isWorking: true,
        isError: false,
        preview: "",
        usageLabel: "",
        status: "Writing…",
        original: action.original ?? state.original,
      };
    case "partial":
      return { ...state, preview: action.preview, status: `Writing… ${action.preview.length} characters` };
    case "ready":
      return {
        ...state,
        isWorking: false,
        isError: false,
        preview: action.preview,
        usageLabel: action.usageLabel,
        status: action.usageLabel ? `Ready to replace · ${action.usageLabel}` : "Ready to replace",
      };
    case "fail":
      return { ...state, isWorking: false, isError: true, status: action.status, toast: { message: action.status, kind: "error" } };
    case "status":
      return { ...state, status: action.status, isError: action.isError ?? false };
    case "apply": {
      const body = state.documents[state.host];
      let { start, end } = action;
      if (body.slice(start, end) !== state.original) {
        // The document changed since the panel opened; re-locate the original passage.
        const found = body.indexOf(state.original);
        if (found < 0) {
          return {
            ...state,
            isError: true,
            status: "Selection changed — re-select and retry",
            toast: { message: "Selection changed — re-select and retry", kind: "error" },
          };
        }
        start = found;
        end = found + state.original.length;
      }
      const applied = applyReplacement(body, start, end, action.rewritten);
      return {
        ...state,
        documents: { ...state.documents, [state.host]: applied.next },
        undoStack: [...state.undoStack, { ...applied.entry, host: state.host }].slice(-undoLimit),
        redoStack: [],
        selection: { start: applied.entry.start, end: applied.entry.end },
        panelOpen: false,
        isWorking: false,
        status: "Replaced",
        isError: false,
        toast: { message: "Replaced in the draft", kind: "ok" },
      };
    }
    case "undo": {
      const last = state.undoStack.at(-1);
      if (!last) {
        return { ...state, status: "There is no replacement to undo yet.", isError: true, toast: { message: "Nothing to undo", kind: "error" } };
      }
      const body = state.documents[last.host as HostId] ?? state.documents[state.host];
      const next = undoReplacement(body, last);
      return {
        ...state,
        documents: { ...state.documents, [last.host]: next },
        undoStack: state.undoStack.slice(0, -1),
        redoStack: [...state.redoStack, last].slice(-undoLimit),
        host: last.host as HostId,
        selection: { start: last.start, end: last.start + last.original.length },
        status: "Undid last replace",
        isError: false,
        toast: { message: "Undid last replace", kind: "ok" },
      };
    }
    case "redo": {
      const last = state.redoStack.at(-1);
      if (!last) {
        return { ...state, status: "There is nothing to redo yet.", isError: true, toast: { message: "Nothing to redo", kind: "error" } };
      }
      const body = state.documents[last.host as HostId] ?? state.documents[state.host];
      const next = redoReplacement(body, last);
      return {
        ...state,
        documents: { ...state.documents, [last.host]: next },
        redoStack: state.redoStack.slice(0, -1),
        undoStack: [...state.undoStack, last].slice(-undoLimit),
        host: last.host as HostId,
        selection: { start: last.start, end: last.end },
        status: "Redid last replace",
        isError: false,
        toast: { message: "Redid last replace", kind: "ok" },
      };
    }
    case "record-history": {
      const latest = state.history[0];
      if (latest && latest.action === action.entry.action && latest.original === action.entry.original && latest.result === action.entry.result) {
        return state;
      }
      // Count and byte budgets are enforced together; an entry too large for
      // the whole budget is skipped with feedback rather than truncated.
      const { history, skippedOversized } = budgetHistory([action.entry, ...state.history]);
      return {
        ...state,
        history,
        ...(skippedOversized
          ? { toast: { message: "An oversized history entry was skipped", kind: "error" as const } }
          : {}),
      };
    }
    case "clear-history":
      return { ...state, history: [], toast: { message: "History cleared", kind: "ok" } };
    case "restore-history":
      // Preview-only restore. No document search and no implicit edit target:
      // the selection is cleared so Replace stays disarmed until the user
      // selects live text through the normal workflow.
      return {
        ...state,
        original: action.entry.original,
        preview: action.entry.result,
        action: action.entry.action,
        tone: action.entry.tone,
        panelOpen: true,
        historyOpen: false,
        selection: null,
        status: "Restored from history — select the passage live to replace it",
        isError: false,
        toast: { message: "Restored a previous rewrite", kind: "ok" },
      };
    case "history-query":
      return { ...state, historyQuery: action.query };
    case "history-action":
      return { ...state, historyAction: action.action };
    case "history-host":
      return state.historyHost === action.host ? state : { ...state, historyHost: action.host };
    case "delete-history-entry": {
      const index = state.history.findIndex((entry) => entry.id === action.id);
      if (index < 0) return state;
      const history = state.history.slice();
      const [removed] = history.splice(index, 1);
      return {
        ...state,
        history,
        lastDeletedHistory: removed,
        lastDeletedHistoryIndex: index,
        toast: { message: "Entry deleted", kind: "ok" },
      };
    }
    case "undo-delete-history": {
      if (!state.lastDeletedHistory) {
        return { ...state, toast: { message: "Nothing to undo", kind: "error" } };
      }
      const history = state.history.slice();
      const index = state.lastDeletedHistoryIndex >= 0 ? Math.min(state.lastDeletedHistoryIndex, history.length) : history.length;
      history.splice(index, 0, state.lastDeletedHistory);
      return {
        ...state,
        history,
        lastDeletedHistory: null,
        lastDeletedHistoryIndex: -1,
        toast: { message: "Entry restored", kind: "ok" },
      };
    }
    case "update-settings": {
      const settings = { ...state.settings, ...action.settings };
      const shortcut = settings.shortcut;
      if (!shortcut.alt && !shortcut.shift && !shortcut.meta && !shortcut.ctrl) {
        settings.shortcut = { ...shortcut, alt: true, shift: true };
      }
      return { ...state, settings };
    }
    case "set-presets":
      return { ...state, presets: action.presets, selectedPresetId: action.selectedPresetId ?? state.selectedPresetId };
    case "toast":
      return { ...state, toast: action.toast };
    case "tick":
      return { ...state, clock: action.clock };
    case "idle":
      return { ...state, isWorking: false };
    default:
      return state;
  }
}

const StudioContext = createContext<{
  state: StudioState;
  dispatch: Dispatch<Action>;
  actions: ReturnType<typeof bindActions>;
} | null>(null);

export function isEditableTarget(target: unknown): boolean {
  if (!(target instanceof HTMLElement)) return false;
  if (target.isContentEditable) return true;
  if (target.closest("[contenteditable='true']")) return true;
  return target.tagName === "INPUT" || target.tagName === "TEXTAREA" || target.tagName === "SELECT";
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isHistoryEntry(value: unknown): value is HistoryEntry {
  if (!isRecord(value)) return false;
  return (
    typeof value.id === "string" &&
    typeof value.createdAt === "string" &&
    typeof value.action === "string" &&
    typeof value.tone === "string" &&
    typeof value.original === "string" &&
    typeof value.result === "string"
  );
}

function validHistoryEntries(value: unknown): HistoryEntry[] {
  return Array.isArray(value) ? value.filter(isHistoryEntry).slice(0, 40) : [];
}

export function sanitizeStoredState(parsed: unknown): Partial<StudioState> {
  if (!isRecord(parsed)) return {};
  const safe: Partial<StudioState> = { ...parsed } as Partial<StudioState>;
  const storedSettings = isRecord(parsed.settings) ? (parsed.settings as Partial<StudioSettings>) : {};
  const storedShortcut = isRecord(storedSettings.shortcut) ? storedSettings.shortcut : {};
  safe.settings = {
    ...defaultSettings,
    ...storedSettings,
    shortcut: { ...defaultSettings.shortcut, ...storedShortcut },
  };
  safe.history = budgetHistory(validHistoryEntries(parsed.history)).history;
  safe.historyHost = parsed.historyHost === "notes" || parsed.historyHost === "mail" || parsed.historyHost === "slack" || parsed.historyHost === "docs" ? parsed.historyHost : "all";
  if (Array.isArray(parsed.undoStack)) safe.undoStack = (parsed.undoStack as Replacement[]).slice(-undoLimit);
  if (Array.isArray(parsed.redoStack)) safe.redoStack = (parsed.redoStack as Replacement[]).slice(-undoLimit);
  return safe;
}

function persistable(state: StudioState) {
  return {
    version: storageVersion,
    host: state.host,
    documents: state.documents,
    action: state.action,
    tone: state.tone,
    length: state.length,
    showDiff: state.showDiff,
    settings: state.settings,
    presets: state.presets,
    selectedPresetId: state.selectedPresetId,
    // History is persisted even while recording is disabled: turning recording
    // off stops new entries, it does not drop existing ones.
    history: budgetHistory(state.history).history,
    historyHost: state.historyHost,
    undoStack: budgetStack(state.undoStack.slice(-undoLimit)),
    redoStack: budgetStack(state.redoStack.slice(-undoLimit)),
    onboardingOpen: state.onboardingOpen,
    onboardingStep: state.onboardingStep,
  };
}

export function degradedPersistable(state: StudioState, dropStacks: boolean) {
  const snapshot = persistable(state);
  return {
    ...snapshot,
    history: [],
    undoStack: dropStacks ? [] : snapshot.undoStack,
    redoStack: dropStacks ? [] : snapshot.redoStack,
  };
}

export function bindActions(
  state: StudioState,
  dispatch: Dispatch<Action>,
  abortRef: { current: AbortController | null },
  generationRef: { current: number } = { current: 0 },
) {
  const selectedText = () => {
    const body = state.documents[state.host];
    if (state.selection && state.selection.end > state.selection.start) {
      return body.slice(state.selection.start, state.selection.end);
    }
    return "";
  };

  const openPanel = () => {
    try {
      const text = validateSelection(selectedText());
      dispatch({ type: "open-panel", original: text });
    } catch (error) {
      dispatch({
        type: "open-panel",
        original: "",
        error: error instanceof Error ? error.message : "No selected text found.",
      });
    }
  };

  const generate = async (nextAction = state.action, nextTone = state.tone, nextLength = state.length) => {
    const text = state.original || selectedText();
    try {
      validateSelection(text);
    } catch (error) {
      dispatch({ type: "fail", status: error instanceof Error ? error.message : "No selected text found." });
      return;
    }

    abortRef.current?.abort();
    const controller = new AbortController();
    abortRef.current = controller;
    const generation = (generationRef.current += 1);
    const isStale = () => generationRef.current !== generation || controller.signal.aborted;
    dispatch({ type: "set-action", action: nextAction });
    dispatch({ type: "set-tone", tone: nextTone });
    dispatch({ type: "set-length", length: nextLength });
    dispatch({ type: "working", original: text });

    try {
      if (state.settings.provider === "openAI") {
        validateAPIKey(state.settings.apiKey);
      }
      const preset = state.presets.find((item) => item.id === state.selectedPresetId) ?? null;
      const extras = { length: nextLength, preset, customInstructions: state.settings.customInstructions };
      const onPartial = (preview: string) => {
        if (isStale()) return;
        dispatch({ type: "partial", preview });
      };
      const result =
        state.settings.provider === "demo"
          ? await streamDemo(text, nextAction, nextTone, onPartial, controller.signal, 8, extras)
          : await streamRemote(
              text,
              nextAction,
              nextTone,
              preset,
              state.settings.customInstructions,
              {
                baseURL:
                  state.settings.baseURL ||
                  (state.settings.provider === "openAI" ? "https://api.openai.com/v1" : "http://127.0.0.1:11434/v1"),
                model: state.settings.model,
                apiKey: state.settings.apiKey,
                authStyle: state.settings.authStyle,
                apiVersion: state.settings.apiVersion,
              },
              nextLength,
              onPartial,
              controller.signal,
            );
      if (isStale()) return;
      const usageLabel = result.usage
        ? tokenCostLabel(state.settings.model, result.usage.promptTokens, result.usage.completionTokens)
        : `≈ ${estimateTokenCount(state.original) + estimateTokenCount(result.text)} tokens (estimated) — cost unavailable`;
      dispatch({ type: "ready", preview: result.text, usageLabel });
      const warning = finishReasonLabel(result.finishReason);
      if (warning) {
        dispatch({ type: "toast", toast: { message: warning, kind: "error" } });
      }
    } catch (error) {
      if (isStale()) return;
      if (error instanceof DOMException && error.name === "AbortError") {
        dispatch({ type: "status", status: "Cancelled" });
        dispatch({ type: "idle" });
        return;
      }
      dispatch({ type: "fail", status: error instanceof Error ? error.message : "Rewrite failed." });
    }
  };

  const apply = () => {
    if (!state.preview || !state.selection) {
      dispatch({ type: "fail", status: "Select text, rewrite it, then replace." });
      return;
    }
    dispatch({ type: "apply", start: state.selection.start, end: state.selection.end, rewritten: state.preview });
    if (state.settings.historyEnabled) {
      dispatch({
        type: "record-history",
        entry: {
          id: crypto.randomUUID(),
          createdAt: new Date().toISOString(),
          action: state.action,
          tone: state.tone,
          original: state.original,
          result: state.preview,
          host: state.host,
        },
      });
    }
  };

  const copyPreview = async () => {
    if (!state.preview) return;
    try {
      await navigator.clipboard.writeText(state.preview);
    } catch {
      dispatch({ type: "status", status: "Copy failed", isError: true });
      dispatch({ type: "toast", toast: { message: "Could not copy to the clipboard", kind: "error" } });
      return;
    }
    dispatch({ type: "status", status: "Copied" });
    dispatch({ type: "toast", toast: { message: "Copied rewrite", kind: "ok" } });
    if (state.settings.historyEnabled) {
      dispatch({
        type: "record-history",
        entry: {
          id: crypto.randomUUID(),
          createdAt: new Date().toISOString(),
          action: state.action,
          tone: state.tone,
          original: state.original,
          result: state.preview,
          host: state.host,
        },
      });
    }
  };

  const cancel = () => {
    abortRef.current?.abort();
    generationRef.current += 1;
    dispatch({ type: "idle" });
    dispatch({ type: "close-panel" });
  };

  const ping = async () => {
    const result = await testConnection(state.settings);
    dispatch({ type: "toast", toast: { message: result.message, kind: result.ok ? "ok" : "error" } });
    return result.message;
  };

  const deleteHistoryEntry = (id: string) => {
    dispatch({ type: "delete-history-entry", id });
  };

  const undoDeleteHistory = () => {
    dispatch({ type: "undo-delete-history" });
  };

  const setHistoryHost = (host: "all" | HostId) => {
    dispatch({ type: "history-host", host });
  };

  return { openPanel, generate, apply, copyPreview, cancel, ping, deleteHistoryEntry, undoDeleteHistory, setHistoryHost, selectedText };
}

export function StudioProvider({ children }: { children: ReactNode }) {
  const [state, dispatch] = useReducer(reduceStudio, undefined, createInitialState);
  const abortRef = useRef<AbortController | null>(null);
  const generationRef = useRef(0);
  const [ready, setReady] = useState(false);
  const persistSnapshot = useRef("");
  const lastPersistAt = useRef(0);

  useEffect(() => {
    try {
      // A newer-format payload always wins: a deliberate empty history must
      // never be repopulated from the legacy key.
      const v2 = localStorage.getItem(storageKey);
      const raw = v2 !== null ? v2 : localStorage.getItem(legacyStorageKey);
      if (raw) {
        const parsed: unknown = JSON.parse(raw);
        const safe = sanitizeStoredState(parsed);
        const storedOnboarding = isRecord(parsed) && typeof parsed.onboardingOpen === "boolean" ? parsed.onboardingOpen : undefined;
        dispatch({
          type: "hydrate",
          state: {
            ...safe,
            onboardingOpen: storedOnboarding ?? !localStorage.getItem(onboardedKey),
          },
        });
      }
    } catch {
      /* keep defaults */
    }
    setReady(true);
  }, []);

  useEffect(() => {
    if (!ready) return;
    const now = Date.now();
    // Partial tokens arrive far faster than storage should be written: throttle
    // while streaming, flush as soon as the stream ends.
    if (!shouldWritePersist(state.isWorking, lastPersistAt.current, now)) return;
    const snapshot = JSON.stringify(persistable(state));
    if (snapshot === persistSnapshot.current) return;
    try {
      localStorage.setItem(storageKey, snapshot);
      persistSnapshot.current = snapshot;
      lastPersistAt.current = now;
    } catch {
      lastPersistAt.current = now;
      // Quota exceeded or storage unavailable: retry with progressively smaller payloads.
      try {
        localStorage.setItem(storageKey, JSON.stringify(degradedPersistable(state, false)));
        persistSnapshot.current = snapshot;
        dispatch({ type: "toast", toast: { message: "Session too large to save — history was not persisted", kind: "error" } });
      } catch {
        try {
          localStorage.setItem(storageKey, JSON.stringify(degradedPersistable(state, true)));
          persistSnapshot.current = snapshot;
          dispatch({ type: "toast", toast: { message: "Session too large to save — history was not persisted", kind: "error" } });
        } catch {
          /* storage unavailable; keep the session in memory */
        }
      }
    }
    try {
      if (!state.onboardingOpen) localStorage.setItem(onboardedKey, "1");
    } catch {
      /* storage unavailable */
    }
  }, [ready, state]);

  useEffect(() => {
    const tick = () => {
      dispatch({ type: "tick", clock: new Date().toLocaleTimeString([], { hour: "numeric", minute: "2-digit" }) });
    };
    tick();
    const id = window.setInterval(tick, 30_000);
    return () => window.clearInterval(id);
  }, []);

  useEffect(() => {
    document.documentElement.dataset.theme = state.settings.theme;
  }, [state.settings.theme]);

  useEffect(() => {
    if (!state.toast) return;
    const id = window.setTimeout(() => dispatch({ type: "toast", toast: null }), 2400);
    return () => window.clearTimeout(id);
  }, [state.toast]);

  const actions = useMemo(() => bindActions(state, dispatch, abortRef, generationRef), [state]);

  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      const shortcut = state.settings.shortcut;
      const editable = isEditableTarget(event.target);
      const key = event.key.toLowerCase();
      const hasModifier = shortcut.alt || shortcut.shift || shortcut.meta || shortcut.ctrl;
      const matchesShortcut =
        hasModifier &&
        key === shortcut.key.toLowerCase() &&
        event.altKey === shortcut.alt &&
        event.shiftKey === shortcut.shift &&
        event.metaKey === shortcut.meta &&
        event.ctrlKey === shortcut.ctrl;
      if (matchesShortcut) {
        event.preventDefault();
        actions.openPanel();
        return;
      }
      if ((event.metaKey || event.ctrlKey) && key === "z" && !event.shiftKey && !state.panelOpen) {
        if (editable) return;
        event.preventDefault();
        dispatch({ type: "undo" });
        return;
      }
      if ((event.metaKey || event.ctrlKey) && (key === "y" || (key === "z" && event.shiftKey)) && !state.panelOpen) {
        if (editable) return;
        event.preventDefault();
        dispatch({ type: "redo" });
        return;
      }
      if (!editable && (event.metaKey || event.ctrlKey) && event.key === ",") {
        event.preventDefault();
        dispatch({ type: "toggle-settings", open: true });
        return;
      }
      if (!editable && (event.metaKey || event.ctrlKey) && event.shiftKey && key === "h") {
        event.preventDefault();
        dispatch({ type: "toggle-history", open: true });
        return;
      }
      if (!state.panelOpen) return;
      if ((event.metaKey || event.ctrlKey) && key === "d") {
        event.preventDefault();
        dispatch({ type: "toggle-diff" });
        return;
      }
      if (event.key === "Escape") {
        event.preventDefault();
        actions.cancel();
      }
      if (event.key === "Enter" && (event.metaKey || event.ctrlKey)) {
        event.preventDefault();
        actions.apply();
      }
      if (!editable && /^[1-9]$/.test(event.key) && !event.metaKey && !event.ctrlKey && !event.altKey) {
        const next = (
          [
            "correct",
            "improve",
            "rewrite",
            "shorten",
            "changeTone",
            "expand",
            "simplify",
            "bullets",
            "continueWriting",
          ] as RewriteAction[]
        )[Number(event.key) - 1];
        if (next) void actions.generate(next, state.tone, state.length);
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [actions, state.panelOpen, state.settings.shortcut, state.tone, state.length]);

  return <StudioContext.Provider value={{ state, dispatch, actions }}>{children}</StudioContext.Provider>;
}

export function useStudio() {
  const value = useContext(StudioContext);
  if (!value) throw new Error("useStudio must be used inside StudioProvider");
  return value;
}

export function shortcutLabel(shortcut: StudioSettings["shortcut"]): string {
  return `${shortcut.ctrl ? "⌃" : ""}${shortcut.alt ? "⌥" : ""}${shortcut.shift ? "⇧" : ""}${shortcut.meta ? "⌘" : ""}${shortcut.key.toUpperCase()}`;
}

export function visibleHistory(state: StudioState): HistoryEntry[] {
  const filtered = filterHistory(state.history, state.historyQuery, state.historyAction);
  if (state.historyHost === "all") return filtered;
  return filtered.filter((entry) => entry.host === state.historyHost);
}

export { defaultSettings };
