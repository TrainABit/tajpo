import { afterEach, describe, expect, it, vi } from "vitest";
import {
  bindActions,
  createInitialState,
  degradedPersistable,
  isEditableTarget,
  reduceStudio,
  sanitizeStoredState,
  visibleHistory,
  type StudioState,
} from "../src/state/store";

afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

function applyOnce(state: StudioState, start: number, end: number, rewritten: string, original: string) {
  return reduceStudio({ ...state, original }, { type: "apply", start, end, rewritten });
}

function makeReplacement(index: number) {
  return { host: "notes", start: index, end: index + 1, original: "a", rewritten: "b" };
}

function fakeHTMLElement(init: { tagName: string; isContentEditable?: boolean; closest?: () => unknown }) {
  const Base = globalThis.HTMLElement as unknown as { new (): Record<string, unknown> };
  class Fake extends Base {
    tagName = init.tagName;
    isContentEditable = init.isContentEditable ?? false;
    closest = init.closest ?? (() => null);
  }
  return new Fake() as unknown as HTMLElement;
}

describe("studio reducer", () => {
  it("applies, undoes, and redoes a replace", () => {
    const withDoc = reduceStudio(createInitialState(), {
      type: "set-document",
      host: "notes",
      body: "teh fox",
    });
    const opened = reduceStudio(withDoc, {
      type: "open-panel",
      original: "teh fox",
    });
    const ready = reduceStudio(opened, { type: "ready", preview: "The fox", usageLabel: "3 tokens" });
    const selected = reduceStudio(ready, { type: "set-selection", selection: { start: 0, end: 7 } });
    const applied = reduceStudio(selected, { type: "apply", start: 0, end: 7, rewritten: "The fox" });
    expect(applied.documents.notes.startsWith("The fox")).toBe(true);
    expect(applied.undoStack).toHaveLength(1);
    expect(applied.toast?.kind).toBe("ok");
    const originalSlice = selected.documents.notes.slice(0, 7);
    const undone = reduceStudio(applied, { type: "undo" });
    expect(undone.documents.notes.startsWith(originalSlice)).toBe(true);
    expect(undone.redoStack).toHaveLength(1);
    const redone = reduceStudio(undone, { type: "redo" });
    expect(redone.undoStack).toHaveLength(1);
    expect(redone.redoStack).toHaveLength(0);
  });

  it("keeps at least one shortcut modifier", () => {
    const next = reduceStudio(createInitialState(), {
      type: "update-settings",
      settings: { shortcut: { alt: false, shift: false, meta: false, ctrl: false, key: "t" } },
    });
    expect(next.settings.shortcut.alt).toBe(true);
    expect(next.settings.shortcut.shift).toBe(true);
  });

  it("hydrates missing host documents", () => {
    const next = reduceStudio(createInitialState(), {
      type: "hydrate",
      state: { documents: { notes: "only notes" } as never },
    });
    expect(next.documents.notes).toBe("only notes");
    expect(next.documents.docs.length).toBeGreaterThan(0);
    expect(next.panelOpen).toBe(false);
    expect(next.toast).toBeNull();
  });

  it("restores a history entry into the panel", () => {
    const entry = {
      id: "1",
      createdAt: "2026-01-01T00:00:00.000Z",
      action: "improve" as const,
      tone: "friendly" as const,
      original: "hello",
      result: "Hello there",
    };
    const withDoc = reduceStudio(createInitialState(), {
      type: "set-document",
      host: "notes",
      body: "please hello now",
    });
    const restored = reduceStudio(withDoc, { type: "restore-history", entry });
    expect(restored.panelOpen).toBe(true);
    expect(restored.preview).toBe("Hello there");
    // Preview-only restore: the live edit target is cleared so Replace stays
    // disarmed until the user selects live text.
    expect(restored.selection).toBeNull();
  });

  it("apply re-locates via indexOf when the captured offsets are stale", () => {
    const base = reduceStudio(createInitialState(), {
      type: "set-document",
      host: "notes",
      body: "draft: teh fox!",
    });
    // Selection was { 7, 14 } when the panel opened, but the user prepended "x " meanwhile.
    const edited = reduceStudio(base, { type: "set-document", host: "notes", body: "x draft: teh fox!" });
    const applied = applyOnce(edited, 7, 14, "the fox", "teh fox");
    expect(applied.documents.notes).toBe("x draft: the fox!");
    expect(applied.undoStack).toHaveLength(1);
    expect(applied.toast?.kind).toBe("ok");
  });

  it("apply fails without modifying the document when the original is gone", () => {
    const edited = reduceStudio(createInitialState(), {
      type: "set-document",
      host: "notes",
      body: "completely different text",
    });
    const applied = applyOnce(edited, 0, 7, "the fox", "teh fox");
    expect(applied.documents.notes).toBe("completely different text");
    expect(applied.undoStack).toHaveLength(0);
    expect(applied.isError).toBe(true);
    expect(applied.status).toContain("re-select");
  });

  it("restore-history clears the selection when the original is absent", () => {
    const entry = {
      id: "1",
      createdAt: "2026-01-01T00:00:00.000Z",
      action: "improve" as const,
      tone: "friendly" as const,
      original: "vanished passage",
      result: "Vanished passage",
    };
    const withSelection = reduceStudio(createInitialState(), {
      type: "set-selection",
      selection: { start: 2, end: 9 },
    });
    const restored = reduceStudio(withSelection, { type: "restore-history", entry });
    expect(restored.panelOpen).toBe(true);
    expect(restored.preview).toBe("Vanished passage");
    expect(restored.selection).toBeNull();
  });

  it("restore-history clears the selection regardless of where the original was", () => {
    const entry = {
      id: "1",
      createdAt: "2026-01-01T00:00:00.000Z",
      action: "improve" as const,
      tone: "friendly" as const,
      original: "dup",
      result: "Dup",
    };
    const withDoc = reduceStudio(createInitialState(), {
      type: "set-document",
      host: "notes",
      body: "dup one two dup",
    });
    const withSelection = reduceStudio(withDoc, { type: "set-selection", selection: { start: 12, end: 15 } });
    const restored = reduceStudio(withSelection, { type: "restore-history", entry });
    expect(restored.panelOpen).toBe(true);
    expect(restored.preview).toBe("Dup");
    expect(restored.selection).toBeNull();
  });

});
describe("studio storage and guards", () => {
  it("caps undo and redo stacks at 50 entries", () => {
    let state = createInitialState();
    for (let i = 0; i < 60; i += 1) {
      state = applyOnce(state, 0, 1, `v${i}`, state.documents.notes.slice(0, 1));
    }
    expect(state.undoStack).toHaveLength(50);
    expect(state.undoStack[0].rewritten).toBe("v10");
    expect(state.undoStack.at(-1)?.rewritten).toBe("v59");

    state = { ...state, redoStack: Array.from({ length: 50 }, (_, i) => makeReplacement(i)) };
    const redone = reduceStudio(state, { type: "redo" });
    expect(redone.undoStack).toHaveLength(50);

    const undone = reduceStudio(
      { ...redone, undoStack: Array.from({ length: 50 }, (_, i) => makeReplacement(i)) },
      { type: "undo" },
    );
    expect(undone.redoStack).toHaveLength(50);
  });

  it("hydrates a payload with missing settings.shortcut using defaults", () => {
    const safe = sanitizeStoredState({ settings: { theme: "light" } });
    const next = reduceStudio(createInitialState(), { type: "hydrate", state: safe });
    expect(next.settings.theme).toBe("light");
    expect(next.settings.shortcut).toEqual({ alt: true, shift: true, meta: false, ctrl: false, key: "t" });
    expect(next.settings.provider).toBe("demo");
  });

  it("drops malformed history entries on hydrate", () => {
    const valid = {
      id: "1",
      createdAt: "2026-01-01T00:00:00.000Z",
      action: "improve",
      tone: "friendly",
      original: "a",
      result: "b",
    };
    const safe = sanitizeStoredState({ history: [valid, { id: "2" }, null, 42, "nope"] });
    expect(safe.history).toEqual([valid]);
    const next = reduceStudio(createInitialState(), { type: "hydrate", state: safe });
    expect(next.history).toEqual([valid]);
  });

  it("dedupes consecutive identical history recordings", () => {
    const entry = {
      id: "1",
      createdAt: "2026-01-01T00:00:00.000Z",
      action: "improve" as const,
      tone: "friendly" as const,
      original: "a",
      result: "b",
    };
    const once = reduceStudio(createInitialState(), { type: "record-history", entry });
    const twice = reduceStudio(once, { type: "record-history", entry: { ...entry, id: "2" } });
    expect(twice.history).toHaveLength(1);
    expect(twice).toBe(once);
  });
});
describe("storage degradation", () => {
  it("degrades the persisted snapshot when quota is exceeded", () => {
    const state = reduceStudio(createInitialState(), {
      type: "record-history",
      entry: {
        id: "1",
        createdAt: "2026-01-01T00:00:00.000Z",
        action: "improve",
        tone: "friendly",
        original: "a",
        result: "b",
      },
    });
    const noHistory = degradedPersistable(state, false);
    expect(noHistory.history).toEqual([]);
    expect(noHistory.undoStack).toEqual(state.undoStack);
    const noStacks = degradedPersistable(state, true);
    expect(noStacks.history).toEqual([]);
    expect(noStacks.undoStack).toEqual([]);
    expect(noStacks.redoStack).toEqual([]);

    // Mirror the persist effect's fallback chain against a throwing localStorage.
    const calls: string[] = [];
    const quotaError = () => {
      const error = new Error("quota");
      error.name = "QuotaExceededError";
      return error;
    };
    const setItem = vi.fn((..._args: unknown[]) => {
      throw quotaError();
    });
    vi.stubGlobal("localStorage", { setItem, getItem: () => null });
    try {
      setItem("tajpo.studio.v2", JSON.stringify(state));
      expect.unreachable("setItem should throw");
    } catch {
      calls.push("full");
      try {
        setItem("tajpo.studio.v2", JSON.stringify(noHistory));
      } catch {
        calls.push("degraded");
        expect(() => setItem("tajpo.studio.v2", JSON.stringify(noStacks))).toThrow();
      }
    }
    expect(calls).toEqual(["full", "degraded"]);
    expect(setItem).toHaveBeenCalledTimes(3);
  });

  it("detects editable keyboard targets", () => {
    vi.stubGlobal("HTMLElement", class {});
    expect(isEditableTarget(null)).toBe(false);
    expect(isEditableTarget({ tagName: "INPUT" })).toBe(false); // not an HTMLElement
    expect(isEditableTarget(fakeHTMLElement({ tagName: "INPUT" }))).toBe(true);
    expect(isEditableTarget(fakeHTMLElement({ tagName: "TEXTAREA" }))).toBe(true);
    expect(isEditableTarget(fakeHTMLElement({ tagName: "SELECT" }))).toBe(true);
    expect(isEditableTarget(fakeHTMLElement({ tagName: "DIV" }))).toBe(false);
    expect(isEditableTarget(fakeHTMLElement({ tagName: "DIV", isContentEditable: true }))).toBe(true);
    expect(isEditableTarget(fakeHTMLElement({ tagName: "SPAN", closest: () => ({}) }))).toBe(true);
  });

  it("stale generation results do not dispatch over a newer run", async () => {
    vi.useFakeTimers();
    try {
      const dispatched: string[] = [];
      const dispatch = (action: { type: string }) => {
        dispatched.push(action.type);
      };
      const abortRef: { current: AbortController | null } = { current: null };
      const generationRef = { current: 0 };
      const state = { ...createInitialState(), original: "teh fox" };
      const first = bindActions(state, dispatch, abortRef, generationRef);
      const run = first.generate("improve", state.tone, state.length);
      // streamDemo emits its first chunk synchronously, before any timer; those
      // dispatches belong to the still-current generation. Everything after the
      // supersede below must be swallowed by the staleness guard.
      const currentCount = dispatched.length;
      generationRef.current += 1; // a newer run supersedes the first one
      await vi.runAllTimersAsync();
      await run;
      const stale = dispatched.slice(currentCount);
      expect(dispatched).toContain("working");
      expect(dispatched).not.toContain("ready");
      expect(stale.filter((type) => type === "partial")).toHaveLength(0);
      expect(dispatched).not.toContain("status");
    } finally {
      vi.useRealTimers();
    }
  });
});

describe("history management", () => {
  type TestHost = "notes" | "mail" | "slack" | "docs";

  function entry(id: string, host?: TestHost) {
    return {
      id,
      createdAt: "2026-01-01T00:00:00.000Z",
      action: "improve" as const,
      tone: "friendly" as const,
      original: `original ${id}`,
      result: `result ${id}`,
      ...(host ? { host } : {}),
    };
  }

  function stateWithHistory(): StudioState {
    return reduceStudio(createInitialState(), {
      type: "record-history",
      entry: entry("1", "notes"),
    }) as StudioState;
  }

  it("deletes exactly one entry and offers undo that restores order", () => {
    let state = reduceStudio(createInitialState(), { type: "record-history", entry: entry("1", "notes") }) as StudioState;
    state = reduceStudio(state, { type: "record-history", entry: entry("2", "mail") }) as StudioState;
    state = reduceStudio(state, { type: "record-history", entry: entry("3", "slack") }) as StudioState;
    // record-history prepends, so the newest entry is first.
    expect(state.history.map((item) => item.id)).toEqual(["3", "2", "1"]);
    const deleted = reduceStudio(state, { type: "delete-history-entry", id: "2" });
    expect(deleted.history.map((item) => item.id)).toEqual(["3", "1"]);
    expect(deleted.lastDeletedHistory?.id).toBe("2");
    expect(deleted.lastDeletedHistoryIndex).toBe(1);
    expect(deleted.toast?.message).toBe("Entry deleted");
    const restored = reduceStudio(deleted, { type: "undo-delete-history" });
    expect(restored.history.map((item) => item.id)).toEqual(["3", "2", "1"]);
    expect(restored.lastDeletedHistory).toBeNull();
    expect(restored.toast?.message).toBe("Entry restored");
  });

  it("does nothing when deleting an unknown id", () => {
    const state = stateWithHistory();
    expect(reduceStudio(state, { type: "delete-history-entry", id: "nope" })).toBe(state);
  });

  it("undo-delete with nothing deleted shows an error toast", () => {
    const state = reduceStudio(createInitialState(), { type: "undo-delete-history" });
    expect(state.history).toHaveLength(0);
    expect(state.toast?.kind).toBe("error");
  });

  it("keeps the delete-undo buffer transient across hydration", () => {
    const deleted = reduceStudio(stateWithHistory(), { type: "delete-history-entry", id: "1" });
    expect(deleted.lastDeletedHistory).not.toBeNull();
    // A hydrated session never resurrects a stale delete-undo buffer.
    const hydrated = reduceStudio(createInitialState(), {
      type: "hydrate",
      state: {
        history: deleted.history,
        lastDeletedHistory: deleted.lastDeletedHistory ?? undefined,
      } as never,
    });
    expect(hydrated.lastDeletedHistory).toBeNull();
    expect(hydrated.lastDeletedHistoryIndex).toBe(-1);
  });

  it("filters visible history by host", () => {
    let state = reduceStudio(createInitialState(), { type: "record-history", entry: entry("1", "notes") }) as StudioState;
    state = reduceStudio(state, { type: "record-history", entry: entry("2", "mail") }) as StudioState;
    state = reduceStudio(state, { type: "record-history", entry: entry("3") }) as StudioState;
    expect(visibleHistory(state)).toHaveLength(3);
    const mailOnly = reduceStudio(state, { type: "history-host", host: "mail" });
    expect(visibleHistory(mailOnly).map((item) => item.id)).toEqual(["2"]);
    // Entries without a host are hidden when a specific host is selected.
    const notesOnly = reduceStudio(state, { type: "history-host", host: "notes" });
    expect(visibleHistory(notesOnly).map((item) => item.id)).toEqual(["1"]);
    expect(reduceStudio(mailOnly, { type: "history-host", host: "all" })).toEqual(state);
    expect(reduceStudio(notesOnly, { type: "history-host", host: "notes" })).toBe(notesOnly);
  });

  it("records the host on history entries created by apply", () => {
    const dispatched: { type: string; entry?: { host?: string }; start?: number; end?: number; rewritten?: string }[] = [];
    const dispatch = (action: (typeof dispatched)[number]) => {
      dispatched.push(action);
    };
    const state: StudioState = {
      ...createInitialState(),
      original: "teh fox",
      preview: "The fox",
      selection: { start: 0, end: 7 },
      documents: { ...createInitialState().documents, notes: "teh fox" },
    };
    const actions = bindActions(state, dispatch, { current: null });
    actions.apply();
    const record = dispatched.find((action) => action.type === "record-history");
    expect(record?.entry?.host).toBe(state.host);
  });

  it("estimates usage and warns on truncation when the server omits usage", async () => {
    const sse =
      'data: {"choices":[{"delta":{"content":"Some rewrite."}}]}\n\n' +
      'data: {"choices":[{"delta":{},"finish_reason":"length"}]}\n\n' +
      "data: [DONE]\n\n";
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => new Response(sse, { status: 200 })),
    );
    const dispatched: { type: string; usageLabel?: string; toast?: { message?: string; kind?: string } }[] = [];
    const dispatch = (action: (typeof dispatched)[number]) => {
      dispatched.push(action);
    };
    const base = createInitialState();
    const state: StudioState = {
      ...base,
      original: "hello world",
      settings: { ...base.settings, provider: "openAI", apiKey: "sk-test", model: "gpt-4o-mini", baseURL: "https://api.openai.com/v1", authStyle: "bearer" },
    };
    const actions = bindActions(state, dispatch as never, { current: null });
    await actions.generate("correct", state.tone, state.length);
    const ready = dispatched.find((action) => action.type === "ready");
    expect(ready?.usageLabel).toMatch(/estimated/i);
    const warning = dispatched.find((action) => action.type === "toast");
    expect(warning?.toast?.message).toMatch(/truncated/i);
    expect(warning?.toast?.kind).toBe("error");
  });
});
