import { useEffect, useRef } from "react";
import { createPortal } from "react-dom";
import { shortcutLabel, useStudio } from "../state/store";

interface KeyCheatSheetProps {
  open: boolean;
  onClose: () => void;
}

const FOCUSABLE = 'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])';

export function KeyCheatSheet({ open, onClose }: KeyCheatSheetProps) {
  const { state } = useStudio();
  const panelRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    if (!open) return;
    const previous = document.activeElement as HTMLElement | null;
    const first = panelRef.current?.querySelector<HTMLElement>(FOCUSABLE);
    first?.focus();
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        event.preventDefault();
        event.stopPropagation();
        onClose();
        return;
      }
      if (event.key === "Tab" && panelRef.current) {
        const focusable = Array.from(panelRef.current.querySelectorAll<HTMLElement>(FOCUSABLE));
        if (focusable.length === 0) return;
        const current = focusable.indexOf(document.activeElement as HTMLElement);
        event.preventDefault();
        const next = event.shiftKey
          ? focusable[(current <= 0 ? focusable.length : current) - 1]
          : focusable[(current + 1) % focusable.length];
        next.focus();
      }
    };
    panelRef.current?.addEventListener("keydown", onKey);
    return () => {
      panelRef.current?.removeEventListener("keydown", onKey);
      previous?.focus();
    };
  }, [open, onClose]);

  if (!open) return null;

  const rows: [string, string][] = [
    [`${shortcutLabel(state.settings.shortcut)}`, "Open the rewrite panel"],
    ["1–9", "Run the matching rewrite action"],
    ["Ctrl/⌘ ↩", "Replace the selection with the preview"],
    ["Esc", "Stop the rewrite / close the panel"],
    ["Ctrl/⌘ Z", "Undo the last replace"],
    ["Ctrl/⌘ Y", "Redo the last replace"],
    ["Ctrl/⌘ D", "Toggle the word diff"],
    ["Ctrl/⌘ ,", "Open settings"],
    ["Ctrl/⌘ ⇧ H", "Open history"],
    ["?", "Toggle this cheat sheet"],
  ];

  return createPortal(
    <div className="modal-backdrop cheat-backdrop" onClick={onClose}>
      <div
        ref={panelRef}
        className="modal cheat-sheet"
        role="dialog"
        aria-modal="true"
        aria-labelledby="cheat-title"
        onClick={(event) => event.stopPropagation()}
      >
        <div className="menu-row">
          <h3 id="cheat-title" style={{ margin: 0, fontFamily: "var(--serif)" }}>
            Keyboard shortcuts
          </h3>
          <button type="button" className="btn-ghost" onClick={onClose}>
            Close
          </button>
        </div>
        <dl className="cheat-rows">
          {rows.map(([keys, description]) => (
            <div className="cheat-row" key={keys}>
              <dt>
                <kbd>{keys}</kbd>
              </dt>
              <dd>{description}</dd>
            </div>
          ))}
        </dl>
      </div>
    </div>,
    document.body,
  );
}
