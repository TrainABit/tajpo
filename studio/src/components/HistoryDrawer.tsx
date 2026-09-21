import { actionMeta, hostDocuments, hosts, rewriteActions } from "../engine";
import { useStudio, visibleHistory } from "../state/store";

export function HistoryDrawer() {
  const { state, dispatch, actions } = useStudio();
  const entries = visibleHistory(state);

  return (
    <aside className="drawer" aria-label="Rewrite history">
      <div className="menu-row">
        <h2 style={{ margin: 0, fontFamily: "var(--serif)" }}>History</h2>
        <button type="button" className="btn-ghost" onClick={() => dispatch({ type: "toggle-history", open: false })}>
          Close
        </button>
      </div>
      <p className="hint">Stored only in this browser. Never uploaded. Click an entry to restore it into the panel.</p>
      <label className="stack">
        Search
        <input
          value={state.historyQuery}
          placeholder="Search original, rewrite, action…"
          onChange={(event) => dispatch({ type: "history-query", query: event.target.value })}
        />
      </label>
      <label className="stack" style={{ margin: "10px 0 14px" }}>
        Action
        <select
          value={state.historyAction}
          onChange={(event) =>
            dispatch({ type: "history-action", action: event.target.value as typeof state.historyAction })
          }
        >
          <option value="all">All actions</option>
          {rewriteActions.map((action) => (
            <option key={action} value={action}>
              {actionMeta[action].title}
            </option>
          ))}
        </select>
      </label>
      <label className="stack" style={{ margin: "10px 0 14px" }}>
        Host
        <select
          value={state.historyHost}
          onChange={(event) => actions.setHistoryHost(event.target.value as typeof state.historyHost)}
        >
          <option value="all">All hosts</option>
          {hosts.map((host) => (
            <option key={host} value={host}>
              {hostDocuments[host].title}
            </option>
          ))}
        </select>
      </label>
      {state.history.length === 0 ? (
        <div className="empty">No rewrites yet. Select text and run Tajpo to fill this list.</div>
      ) : entries.length === 0 ? (
        <div className="empty">No history matches that search.</div>
      ) : (
        entries.map((entry) => (
          <div key={entry.id} className="history-item-row">
            <button
              type="button"
              className="history-item"
              onClick={() => dispatch({ type: "restore-history", entry })}
            >
              <strong>
                {actionMeta[entry.action].title}
                {entry.action === "changeTone" ? ` · ${entry.tone}` : ""}
                {entry.host ? ` · ${hostDocuments[entry.host]?.title ?? entry.host}` : ""}
              </strong>
              <small className="hint">{new Date(entry.createdAt).toLocaleString()}</small>
              <p>{entry.result}</p>
            </button>
            <button
              type="button"
              className="history-delete"
              aria-label="Delete entry"
              title="Delete entry"
              onClick={() => actions.deleteHistoryEntry(entry.id)}
            >
              ✕
            </button>
          </div>
        ))
      )}
      <button
        type="button"
        className="btn-danger"
        disabled={state.history.length === 0}
        onClick={() => dispatch({ type: "clear-history" })}
      >
        Clear history
      </button>
    </aside>
  );
}
