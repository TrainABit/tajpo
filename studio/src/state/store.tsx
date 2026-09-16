import {
  createContext,
  useContext,
  useEffect,
  useMemo,
  useReducer,
  useRef,
  type Dispatch,
  type ReactNode,
} from "react";
import {
  defaultPresets,
  hostDocuments,
  streamDemo,
  streamRemote,
  tokenCostLabel,
  validateAPIKey,
  validateSelection,
  type HostId,
  type LLMAuthStyle,
  type LLMProvider,
  type RewriteAction,
  type RewriteTone,
  type WritingPreset,
} from "../engine";

export interface HistoryEntry {
  id: string;
  createdAt: string;
  action: RewriteAction;
  tone: RewriteTone;
  original: string;
  result: string;
}

export interface StudioSettings {
  provider: LLMProvider;
  model: string;
  baseURL: string;
  apiKey: string;
  authStyle: LLMAuthStyle;
  apiVersion: string;
  customInstructions: string;
  historyEnabled: boolean;
  shortcut: { alt: boolean; shift: boolean; meta: boolean; ctrl: boolean; key: string };
}

export interface StudioState {
  host: HostId;
  documents: Record<HostId, string>;
  selection: { start: number; end: number } | null;
  original: string;
  preview: string;
  action: RewriteAction;
  tone: RewriteTone;
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
  lastReplacement: { start: number; end: number; original: string; rewritten: string } | null;
  clock: string;
}

type Action =
  | { type: "hydrate"; state: Partial<StudioState> }
  | { type: "set-host"; host: HostId }
  | { type: "set-document"; host: HostId; body: string }
  | { type: "set-selection"; selection: { start: number; end: number } | null }
  | { type: "set-action"; action: RewriteAction }
  | { type: "set-tone"; tone: RewriteTone }
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
  | { type: "record-history"; entry: HistoryEntry }
  | { type: "clear-history" }
  | { type: "restore-history"; entry: HistoryEntry }
  | { type: "update-settings"; settings: Partial<StudioSettings> }
  | { type: "set-presets"; presets: WritingPreset[]; selectedPresetId?: string }
  | { type: "tick"; clock: string }
  | { type: "idle" };

const storageKey = "tajpo.studio.v1";

const defaultSettings: StudioSettings = {
  provider: "demo",
  model: "tajpo-demo",
  baseURL: import.meta.env.VITE_OPENAI_BASE_URL ?? "",
  apiKey: import.meta.env.VITE_OPENAI_API_KEY ?? "",
  authStyle: "none",
  apiVersion: "",
  customInstructions: "",
  historyEnabled: true,
  shortcut: { alt: true, shift: true, meta: false, ctrl: false, key: "t" },
};

function emptyDocuments(): Record<HostId, string> {
  return {
    notes: hostDocuments.notes.body,
    mail: hostDocuments.mail.body,
    slack: hostDocuments.slack.body,
  };
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
    lastReplacement: null,
    clock: "9:41",
  };
}

function reducer(state: StudioState, action: Action): StudioState {
  switch (action.type) {
    case "hydrate":
      return { ...state, ...action.state, isWorking: false, menuOpen: false, panelOpen: false };
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
      return {
        ...state,
        onboardingOpen: action.open,
        onboardingStep: action.step ?? state.onboardingStep,
      };
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
      return {
        ...state,
        preview: action.preview,
        status: `Writing… ${action.preview.length} characters`,
      };
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
      return { ...state, isWorking: false, isError: true, status: action.status };
    case "status":
      return { ...state, status: action.status, isError: action.isError ?? false };
    case "apply": {
      const body = state.documents[state.host];
      const next = body.slice(0, action.start) + action.rewritten + body.slice(action.end);
      return {
        ...state,
        documents: { ...state.documents, [state.host]: next },
        lastReplacement: {
          start: action.start,
          end: action.start + action.rewritten.length,
          original: body.slice(action.start, action.end),
          rewritten: action.rewritten,
        },
        selection: { start: action.start, end: action.start + action.rewritten.length },
        panelOpen: false,
        isWorking: false,
        status: "Replaced",
        isError: false,
      };
    }
    case "undo": {
      if (!state.lastReplacement) {
        return { ...state, status: "There is no replacement to undo yet.", isError: true };
      }
      const { start, end, original } = state.lastReplacement;
      const body = state.documents[state.host];
      const next = body.slice(0, start) + original + body.slice(end);
      return {
        ...state,
        documents: { ...state.documents, [state.host]: next },
        lastReplacement: null,
        selection: { start, end: start + original.length },
        status: "Undid last replace",
        isError: false,
      };
    }
    case "record-history":
      return { ...state, history: [action.entry, ...state.history].slice(0, 40) };
    case "clear-history":
      return { ...state, history: [] };
    case "restore-history":
      return {
        ...state,
        original: action.entry.original,
        preview: action.entry.result,
        action: action.entry.action,
        tone: action.entry.tone,
        panelOpen: true,
        historyOpen: false,
        status: "Restored from history",
        isError: false,
      };
    case "update-settings":
      return { ...state, settings: { ...state.settings, ...action.settings } };
    case "set-presets":
      return {
        ...state,
        presets: action.presets,
        selectedPresetId: action.selectedPresetId ?? state.selectedPresetId,
      };
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

function persistable(state: StudioState) {
  return {
    host: state.host,
    documents: state.documents,
    action: state.action,
    tone: state.tone,
    settings: state.settings,
    presets: state.presets,
    selectedPresetId: state.selectedPresetId,
    history: state.settings.historyEnabled ? state.history : [],
    onboardingOpen: state.onboardingOpen,
    onboardingStep: state.onboardingStep,
  };
}

function bindActions(
  state: StudioState,
  dispatch: Dispatch<Action>,
  abortRef: { current: AbortController | null },
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

  const generate = async (nextAction = state.action, nextTone = state.tone) => {
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
    dispatch({ type: "set-action", action: nextAction });
    dispatch({ type: "set-tone", tone: nextTone });
    dispatch({ type: "working", original: text });

    try {
      if (state.settings.provider !== "demo" && state.settings.provider === "openAI") {
        validateAPIKey(state.settings.apiKey);
      }
      const preset = state.presets.find((item) => item.id === state.selectedPresetId) ?? null;
      const onPartial = (preview: string) => dispatch({ type: "partial", preview });
      const result =
        state.settings.provider === "demo"
          ? await streamDemo(text, nextAction, nextTone, onPartial, controller.signal)
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
              onPartial,
              controller.signal,
            );
      const usageLabel = result.usage
        ? tokenCostLabel(state.settings.model, result.usage.promptTokens, result.usage.completionTokens)
        : "";
      dispatch({ type: "ready", preview: result.text, usageLabel });
    } catch (error) {
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
    dispatch({
      type: "apply",
      start: state.selection.start,
      end: state.selection.end,
      rewritten: state.preview,
    });
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
        },
      });
    }
  };

  const copyPreview = async () => {
    if (!state.preview) return;
    await navigator.clipboard.writeText(state.preview);
    dispatch({ type: "status", status: "Copied" });
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
        },
      });
    }
  };

  const cancel = () => {
    abortRef.current?.abort();
    dispatch({ type: "idle" });
    dispatch({ type: "close-panel" });
  };

  return { openPanel, generate, apply, copyPreview, cancel };
}

export function StudioProvider({ children }: { children: ReactNode }) {
  const [state, dispatch] = useReducer(reducer, undefined, createInitialState);
  const abortRef = useRef<AbortController | null>(null);
  const hydrated = useRef(false);

  useEffect(() => {
    try {
      const raw = localStorage.getItem(storageKey);
      if (raw) {
        const parsed = JSON.parse(raw) as Partial<StudioState> & { completedOnboarding?: boolean };
        dispatch({
          type: "hydrate",
          state: {
            ...parsed,
            onboardingOpen: parsed.onboardingOpen ?? !localStorage.getItem("tajpo.studio.onboarded"),
          },
        });
      }
    } catch {
      /* keep defaults */
    }
    hydrated.current = true;
  }, []);

  useEffect(() => {
    if (!hydrated.current) return;
    localStorage.setItem(storageKey, JSON.stringify(persistable(state)));
    if (!state.onboardingOpen) localStorage.setItem("tajpo.studio.onboarded", "1");
  }, [state]);

  useEffect(() => {
    const tick = () => {
      dispatch({
        type: "tick",
        clock: new Date().toLocaleTimeString([], { hour: "numeric", minute: "2-digit" }),
      });
    };
    tick();
    const id = window.setInterval(tick, 30_000);
    return () => window.clearInterval(id);
  }, []);

  const actions = useMemo(() => bindActions(state, dispatch, abortRef), [state]);

  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      const shortcut = state.settings.shortcut;
      const key = event.key.toLowerCase();
      const matchesShortcut =
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
      if (!state.panelOpen) return;
      if (event.key === "Escape") {
        event.preventDefault();
        actions.cancel();
      }
      if (event.key === "Enter" && event.metaKey) {
        event.preventDefault();
        actions.apply();
      }
      if (/^[1-9]$/.test(event.key) && !event.metaKey && !event.ctrlKey && !event.altKey) {
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
        if (next) void actions.generate(next, state.tone);
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [actions, state.panelOpen, state.settings.shortcut, state.tone]);

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

export { defaultSettings };
