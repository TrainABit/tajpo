import { useEffect, useState } from "react";
import { actionMeta, rewriteActions, rewriteTones, type RewriteLength } from "../engine";
import { isEditableTarget, shortcutLabel, useStudio } from "../state/store";
import { KeyCheatSheet } from "./KeyCheatSheet";

export function MenuBar() {
  const { state, dispatch, actions } = useStudio();
  const [openMenu, setOpenMenu] = useState<"file" | "edit" | null>(null);
  const [shortcutsOpen, setShortcutsOpen] = useState(false);

  const closeMenus = () => setOpenMenu(null);

  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "?" && !event.metaKey && !event.ctrlKey && !event.altKey && !isEditableTarget(event.target)) {
        event.preventDefault();
        setShortcutsOpen((open) => !open);
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);

  return (
    <header className="menubar">
      <div className="menubar-left">
        <span className="brand">Tajpo Studio</span>
        <div className="menu-slot">
          <button
            type="button"
            className="ghost-toggle"
            data-active={openMenu === "file"}
            onClick={() => setOpenMenu(openMenu === "file" ? null : "file")}
          >
            File
          </button>
          {openMenu === "file" ? (
            <div className="menu-mini" role="menu">
              <button type="button" role="menuitem" onClick={() => { dispatch({ type: "toggle-settings", open: true }); closeMenus(); }}>
                Settings…
              </button>
              <button type="button" role="menuitem" onClick={() => { dispatch({ type: "toggle-history", open: true }); closeMenus(); }}>
                History
              </button>
              <button
                type="button"
                role="menuitem"
                onClick={() => {
                  setShortcutsOpen(true);
                  closeMenus();
                }}
              >
                Shortcuts…
              </button>
              <button
                type="button"
                role="menuitem"
                onClick={() => {
                  dispatch({ type: "set-onboarding", open: true, step: 0 });
                  closeMenus();
                }}
              >
                Replay onboarding
              </button>
            </div>
          ) : null}
        </div>
        <div className="menu-slot">
          <button
            type="button"
            className="ghost-toggle"
            data-active={openMenu === "edit"}
            onClick={() => setOpenMenu(openMenu === "edit" ? null : "edit")}
          >
            Edit
          </button>
          {openMenu === "edit" ? (
            <div className="menu-mini" role="menu">
              <button type="button" role="menuitem" disabled={state.undoStack.length === 0} onClick={() => { dispatch({ type: "undo" }); closeMenus(); }}>
                Undo replace
              </button>
              <button type="button" role="menuitem" disabled={state.redoStack.length === 0} onClick={() => { dispatch({ type: "redo" }); closeMenus(); }}>
                Redo replace
              </button>
            </div>
          ) : null}
        </div>
      </div>
      <div className="menubar-right">
        <button
          type="button"
          className="ghost-toggle"
          aria-label={state.settings.theme === "light" ? "Switch to dark theme" : "Switch to light theme"}
          onClick={() =>
            dispatch({
              type: "update-settings",
              settings: { theme: state.settings.theme === "light" ? "dark" : "light" },
            })
          }
        >
          {state.settings.theme === "light" ? "Dark" : "Light"}
        </button>
        <span>{state.clock}</span>
        <button
          type="button"
          className="tajpo-trigger"
          data-active={state.menuOpen}
          aria-expanded={state.menuOpen}
          aria-haspopup="dialog"
          onClick={() => {
            closeMenus();
            dispatch({ type: "toggle-menu" });
          }}
        >
          <span
            className={`dot ${state.isError ? "error" : ""} ${state.isWorking ? "work" : ""}`}
            aria-hidden="true"
          />
          Tajpo
        </button>
      </div>
      {state.menuOpen ? (
        <div className="menu-pop" role="dialog" aria-label="Tajpo menu">
          <div className="menu-row">
            <div>
              <h3>Tajpo</h3>
              <small className="hint">{providerTitle(state.settings.provider)}</small>
            </div>
            <span className={`status-pill ${state.isError ? "error" : ""}`}>{state.status}</span>
          </div>
          <div className="chips">
            {rewriteActions.map((action) => (
              <button
                key={action}
                type="button"
                className="chip"
                data-active={state.action === action}
                onClick={() => dispatch({ type: "set-action", action })}
              >
                {actionMeta[action].title}
                <small>{actionMeta[action].digit}</small>
              </button>
            ))}
          </div>
          <div className="split">
            {(["shorter", "same", "longer"] as RewriteLength[]).map((length) => (
              <button
                key={length}
                type="button"
                className="chip"
                data-active={state.length === length}
                onClick={() => dispatch({ type: "set-length", length })}
              >
                {length}
              </button>
            ))}
          </div>
          {state.action === "changeTone" ? (
            <label className="stack">
              Tone
              <select
                value={state.tone}
                onChange={(event) =>
                  dispatch({ type: "set-tone", tone: event.target.value as (typeof rewriteTones)[number] })
                }
              >
                {rewriteTones.map((tone) => (
                  <option key={tone} value={tone}>
                    {tone}
                  </option>
                ))}
              </select>
            </label>
          ) : null}
          <button type="button" className="btn" onClick={actions.openPanel} disabled={state.isWorking}>
            {state.isWorking ? "Working…" : "Open rewrite panel"}
          </button>
          <div className="actions-row">
            <button type="button" className="btn-ghost" disabled={state.undoStack.length === 0} onClick={() => dispatch({ type: "undo" })}>
              Undo
            </button>
            <button type="button" className="btn-ghost" disabled={state.redoStack.length === 0} onClick={() => dispatch({ type: "redo" })}>
              Redo
            </button>
            <button type="button" className="btn-ghost" onClick={() => dispatch({ type: "toggle-history", open: true })}>
              History
            </button>
            <button type="button" className="btn-ghost" onClick={() => dispatch({ type: "toggle-settings", open: true })}>
              Settings
            </button>
          </div>
          <p className="hint" style={{ marginTop: 12 }}>
            {shortcutLabel(state.settings.shortcut)} opens the panel · Accessibility is simulated in Studio
          </p>
        </div>
      ) : null}
      <KeyCheatSheet open={shortcutsOpen} onClose={() => setShortcutsOpen(false)} />
    </header>
  );
}

function providerTitle(provider: string): string {
  if (provider === "demo") return "On-device demo";
  if (provider === "openAI") return "OpenAI";
  return "Local server";
}
