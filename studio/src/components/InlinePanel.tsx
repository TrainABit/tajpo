import { useEffect } from "react";
import { actionMeta, rewriteActions, rewriteTones } from "../engine";
import { shortcutLabel, useStudio } from "../state/store";

export function InlinePanel() {
  const { state, dispatch, actions } = useStudio();

  useEffect(() => {
    if (state.panelOpen && state.original && !state.preview && !state.isWorking && !state.isError) {
      void actions.generate();
    }
  }, [state.panelOpen, state.original, state.preview, state.isWorking, state.isError, actions]);

  const progress = Math.min(state.preview.length / Math.max(state.original.length, 1), 1);

  return (
    <section className="panel" role="dialog" aria-label="Tajpo rewrite panel" style={{ top: "18%", left: "50%", transform: "translateX(-50%)" }}>
      <div className="menu-row">
        <h3 style={{ margin: 0, fontFamily: "var(--serif)" }}>Tajpo</h3>
        <span className={`status-pill ${state.isError ? "error" : ""}`}>{state.status}</span>
      </div>
      <div className="chips" style={{ gridTemplateColumns: "repeat(9, minmax(0, 1fr))" }}>
        {rewriteActions.map((action) => (
          <button
            key={action}
            type="button"
            className="chip"
            data-active={state.action === action}
            title={actionMeta[action].subtitle}
            onClick={() => void actions.generate(action, state.tone)}
          >
            {actionMeta[action].title}
            <small>{actionMeta[action].digit}</small>
          </button>
        ))}
      </div>
      {state.action === "changeTone" ? (
        <div className="split" style={{ marginBottom: 10 }}>
          {rewriteTones.map((tone) => (
            <button
              key={tone}
              type="button"
              className="chip"
              data-active={state.tone === tone}
              onClick={() => void actions.generate("changeTone", tone)}
            >
              {tone}
            </button>
          ))}
        </div>
      ) : null}
      {state.isWorking ? (
        <div className="progress" aria-hidden="true">
          <span style={{ width: `${Math.max(progress * 100, 8)}%` }} />
        </div>
      ) : null}
      <div className="panel columns">
        <div>
          <div className="eyebrow">Original</div>
          <div className={`column ${state.original ? "" : "empty"}`}>
            {state.original || `Select text, then press ${shortcutLabel(state.settings.shortcut)}.`}
          </div>
        </div>
        <div>
          <div className="eyebrow">Rewrite</div>
          <div className={`column ${state.preview ? "" : "empty"} ${state.isError && !state.preview ? "error" : ""}`}>
            {state.preview ? (
              <>
                {state.preview}
                {state.isWorking ? <span className="caret">▍</span> : null}
              </>
            ) : (
              state.status
            )}
          </div>
        </div>
      </div>
      <div className="actions-row">
        <button type="button" className="btn" disabled={!state.preview || state.isWorking} onClick={actions.apply}>
          Replace
        </button>
        <button type="button" className="btn-ghost" disabled={!state.preview} onClick={() => void actions.copyPreview()}>
          Copy
        </button>
        <button type="button" className="btn-ghost" disabled={state.isWorking} onClick={() => void actions.generate()}>
          Retry
        </button>
        <button type="button" className="btn-ghost" onClick={() => dispatch({ type: "undo" })}>
          Undo
        </button>
        <span className="hint" style={{ marginLeft: "auto", alignSelf: "center" }}>
          ⌘↩ replace · esc close · 1–9 actions
        </span>
        <button type="button" className="btn-ghost" onClick={actions.cancel}>
          Close
        </button>
      </div>
    </section>
  );
}
