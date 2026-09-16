import { useRef } from "react";
import { hostDocuments } from "../engine";
import { useStudio } from "../state/store";

export function HostWindow() {
  const { state, dispatch } = useStudio();
  const area = useRef<HTMLTextAreaElement>(null);
  const host = hostDocuments[state.host];

  const syncSelection = () => {
    const el = area.current;
    if (!el) return;
    dispatch({ type: "set-selection", selection: { start: el.selectionStart, end: el.selectionEnd } });
  };

  return (
    <section className="window" aria-label={host.title}>
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
      </div>
      <label className="sr-only" htmlFor="tajpo-editor">
        {host.title} document
      </label>
      <textarea
        id="tajpo-editor"
        ref={area}
        className="editor"
        value={state.documents[state.host]}
        onChange={(event) => dispatch({ type: "set-document", host: state.host, body: event.target.value })}
        onSelect={syncSelection}
        onKeyUp={syncSelection}
        onMouseUp={syncSelection}
        spellCheck={false}
      />
    </section>
  );
}
