import { useEffect } from "react";
import { actionMeta, countWords, rewriteActions, rewriteTones, wordDiff } from "../engine";
import { shortcutLabel, useStudio } from "../state/store";
import type { RewriteLength } from "../engine";

const lengths: { id: RewriteLength; label: string }[] = [
  { id: "shorter", label: "Shorter" },
  { id: "same", label: "Same length" },
  { id: "longer", label: "Longer" },
];

export function InlinePanel() {
  const { state, dispatch, actions } = useStudio();
  const preset = state.presets.find((item) => item.id === state.selectedPresetId);
  const hasInstructions = Boolean(state.settings.customInstructions.trim());

  useEffect(() => {
    if (state.panelOpen && state.original && !state.preview && !state.isWorking && !state.isError) {
      void actions.generate();
    }
  }, [state.panelOpen, state.original, state.preview, state.isWorking, state.isError, actions]);

  const progress = Math.min(state.preview.length / Math.max(state.original.length, 1), 1);
  const previewTokens = state.showDiff && state.preview ? wordDiff(state.original, state.preview) : null;

  return (
    <section className="panel" role="dialog" aria-label="Tajpo rewrite panel">
      <div className="menu-row">
        <div>
          <h3 style={{ margin: 0, fontFamily: "var(--serif)" }}>Tajpo</h3>
          <small className="hint">
            {preset?.name ?? "No preset"}
            {hasInstructions ? " · custom instructions on" : ""}
          </small>
        </div>
        <span className={`status-pill ${state.isError ? "error" : ""}`}>{state.status}</span>
      </div>
      <div className="chips" style={{ gridTemplateColumns: "repeat(auto-fit, minmax(72px, 1fr))" }}>
        {rewriteActions.map((action) => (
          <button
            key={action}
            type="button"
            className="chip"
            data-active={state.action === action}
            title={actionMeta[action].subtitle}
            onClick={() => void actions.generate(action, state.tone, state.length)}
          >
            {actionMeta[action].title}
            <small>{actionMeta[action].digit}</small>
          </button>
        ))}
      </div>
      <div className="split">
        {lengths.map((item) => (
          <button
            key={item.id}
            type="button"
            className="chip"
            data-active={state.length === item.id}
            onClick={() => void actions.generate(state.action, state.tone, item.id)}
          >
            {item.label}
          </button>
        ))}
        <button type="button" className="chip" data-active={state.showDiff} onClick={() => dispatch({ type: "toggle-diff" })}>
          Show diff
        </button>
      </div>
      {state.action === "changeTone" ? (
        <div className="split">
          {rewriteTones.map((tone) => (
            <button
              key={tone}
              type="button"
              className="chip"
              data-active={state.tone === tone}
              onClick={() => void actions.generate("changeTone", tone, state.length)}
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
      <div className="columns">
        <div>
          <div className="eyebrow">Original · {countWords(state.original)} words</div>
          <div className={`column ${state.original ? "" : "empty"}`}>
            {state.original || `Select text, then press ${shortcutLabel(state.settings.shortcut)}.`}
          </div>
        </div>
        <div>
          <div className="eyebrow">Rewrite · {countWords(state.preview)} words</div>
          <div className={`column ${state.preview ? "" : "empty"} ${state.isError && !state.preview ? "error" : ""}`}>
            {previewTokens ? (
              <>
                {previewTokens.map((token, index) => (
                  <span key={`${token.kind}-${index}`} className={token.kind === "same" ? undefined : `diff-${token.kind}`}>
                    {token.text}
                  </span>
                ))}
                {state.isWorking ? <span className="caret">▍</span> : null}
              </>
            ) : state.preview ? (
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
        <button type="button" className="btn-ghost" disabled={state.isWorking || !state.original} onClick={() => void actions.generate()}>
          Retry
        </button>
        <button type="button" className="btn-ghost" disabled={state.undoStack.length === 0} onClick={() => dispatch({ type: "undo" })}>
          Undo
        </button>
        <button type="button" className="btn-ghost" disabled={state.redoStack.length === 0} onClick={() => dispatch({ type: "redo" })}>
          Redo
        </button>
        <span className="hint" style={{ marginLeft: "auto", alignSelf: "center" }}>
          Ctrl/⌘↩ replace · esc close · 1–9 actions · Ctrl/⌘D diff
        </span>
        <button type="button" className="btn-ghost" onClick={actions.cancel}>
          Close
        </button>
      </div>
    </section>
  );
}
