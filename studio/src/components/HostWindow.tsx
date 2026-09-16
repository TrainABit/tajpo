import { useEffect, useRef } from "react";
import { countWords, hostDocuments } from "../engine";
import { useStudio } from "../state/store";

export function HostWindow() {
  const { state, dispatch } = useStudio();
  const area = useRef<HTMLTextAreaElement>(null);
  const fromEditor = useRef(false);
  const host = hostDocuments[state.host];
  const body = state.documents[state.host];
  const selected = state.selection
    ? body.slice(state.selection.start, state.selection.end)
    : "";
  const hasSelection = Boolean(state.selection && state.selection.end > state.selection.start);

  const syncSelection = () => {
    const el = area.current;
    if (!el) return;
    fromEditor.current = true;
    dispatch({ type: "set-selection", selection: { start: el.selectionStart, end: el.selectionEnd } });
  };

  useEffect(() => {
    const el = area.current;
    if (!el || !state.selection) return;
    if (fromEditor.current) {
      fromEditor.current = false;
      return;
    }
    el.focus();
    el.setSelectionRange(state.selection.start, state.selection.end);
  }, [state.selection, state.host, body]);

  const selectAll = () => {
    const el = area.current;
    if (!el) return;
    el.focus();
    el.select();
    syncSelection();
  };

  return (
    <section className="window" data-host={state.host} aria-label={host.title}>
      <div className="window-title">
        <div className="traffic" aria-hidden="true">
          <span className="r" />
          <span className="y" />
          <span className="g" />
        </div>
        <div>
          <h2>{host.title}</h2>
          <p>{host.subtitle}</p>
        </div>
        <div className="window-tools">
          <button type="button" className="ghost-toggle" onClick={selectAll}>
            Select all
          </button>
          <button
            type="button"
            className="ghost-toggle"
            onClick={() => dispatch({ type: "set-document", host: state.host, body: host.body })}
          >
            Reset sample
          </button>
        </div>
      </div>
      <div className="host-chrome">{host.chrome}</div>
      {state.host === "mail" ? (
        <div className="mail-fields" aria-hidden="true">
          <div>
            <span>To</span> design@example.com
          </div>
          <div>
            <span>Subject</span> Tomorrow
          </div>
        </div>
      ) : null}
      {state.host === "slack" ? (
        <div className="slack-meta" aria-hidden="true">
          <strong>#writing</strong>
          <span>Maya, you, Tajpo</span>
        </div>
      ) : null}
      <label className="sr-only" htmlFor="tajpo-editor">
        {host.title} document
      </label>
      <textarea
        id="tajpo-editor"
        ref={area}
        className="editor"
        value={body}
        onChange={(event) => dispatch({ type: "set-document", host: state.host, body: event.target.value })}
        onSelect={syncSelection}
        onKeyUp={syncSelection}
        onMouseUp={syncSelection}
        spellCheck={false}
      />
      <div className="window-status">
        <span>
          {hasSelection
            ? `${countWords(selected)} words selected`
            : "Select a passage to rewrite. Tajpo will not guess a selection."}
        </span>
        <span>
          {countWords(body)} words · {body.length} characters
        </span>
      </div>
    </section>
  );
}
