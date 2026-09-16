import { actionMeta, rewriteActions, rewriteTones } from "../engine";
import { shortcutLabel, useStudio } from "../state/store";

export function MenuBar() {
  const { state, dispatch, actions } = useStudio();

  return (
    <header className="menubar">
      <div className="menubar-left">
        <span className="brand">Tajpo Studio</span>
        <span>File</span>
        <span>Edit</span>
      </div>
      <div className="menubar-right">
        <span>{state.clock}</span>
        <button
          type="button"
          className="tajpo-trigger"
          data-active={state.menuOpen}
          aria-expanded={state.menuOpen}
          aria-haspopup="dialog"
          onClick={() => dispatch({ type: "toggle-menu" })}
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
            <span className={`status-pill ${state.isError ? "error" : ""}`}>
              {state.status}
            </span>
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
            <button type="button" className="btn-ghost" onClick={() => dispatch({ type: "undo" })}>
              Undo
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
    </header>
  );
}

function providerTitle(provider: string): string {
  if (provider === "demo") return "On-device demo";
  if (provider === "openAI") return "OpenAI";
  return "Local server";
}
