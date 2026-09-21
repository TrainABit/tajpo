import { useStudio } from "../state/store";

export function Toast() {
  const { state, actions } = useStudio();
  if (!state.toast) return null;
  return (
    <div className={`toast ${state.toast.kind === "error" ? "error" : "ok"}`} role="status" aria-live="polite">
      <span>{state.toast.message}</span>
      {state.lastDeletedHistory ? (
        <button type="button" className="toast-undo" onClick={actions.undoDeleteHistory}>
          Undo
        </button>
      ) : null}
    </div>
  );
}
