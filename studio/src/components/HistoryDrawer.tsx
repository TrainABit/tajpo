import { actionMeta } from "../engine";
import { useStudio } from "../state/store";

export function HistoryDrawer() {
  const { state, dispatch } = useStudio();

  return (
    <aside className="drawer" aria-label="Rewrite history">
      <div className="menu-row">
        <h2 style={{ margin: 0, fontFamily: "var(--serif)" }}>History</h2>
        <button type="button" className="btn-ghost" onClick={() => dispatch({ type: "toggle-history", open: false })}>
          Close
        </button>
      </div>
      <p className="hint">Stored only in this browser. Never uploaded.</p>
      {state.history.length === 0 ? (
        <div className="empty">No rewrites yet. Select text and run Tajpo to fill this list.</div>
      ) : (
        state.history.map((entry) => (
          <button
            key={entry.id}
            type="button"
            className="history-item"
            onClick={() => dispatch({ type: "restore-history", entry })}
          >
            <strong>
              {actionMeta[entry.action].title}
              {entry.action === "changeTone" ? ` · ${entry.tone}` : ""}
            </strong>
            <small className="hint">{new Date(entry.createdAt).toLocaleString()}</small>
            <p>{entry.result}</p>
          </button>
        ))
      )}
      <button type="button" className="btn-danger" disabled={state.history.length === 0} onClick={() => dispatch({ type: "clear-history" })}>
        Clear history
      </button>
    </aside>
  );
}
