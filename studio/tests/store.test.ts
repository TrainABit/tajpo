import { describe, expect, it } from "vitest";
import { createInitialState, reduceStudio } from "../src/state/store";

describe("studio reducer", () => {
  it("applies, undoes, and redoes a replace", () => {
    const opened = reduceStudio(createInitialState(), {
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
    expect(restored.selection).toEqual({ start: 7, end: 12 });
  });
});
