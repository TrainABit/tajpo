import { useStudio } from "../state/store";

export function Toast() {
  const { state } = useStudio();
  if (!state.toast) return null;
  return (
    <div className={`toast ${state.toast.kind === "error" ? "error" : "ok"}`} role="status" aria-live="polite">
      {state.toast.message}
    </div>
  );
}
