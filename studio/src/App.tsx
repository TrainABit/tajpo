import { HistoryDrawer } from "./components/HistoryDrawer";
import { HostWindow } from "./components/HostWindow";
import { InlinePanel } from "./components/InlinePanel";
import { MenuBar } from "./components/MenuBar";
import { Onboarding } from "./components/Onboarding";
import { SettingsModal } from "./components/SettingsModal";
import { Toast } from "./components/Toast";
import { hosts, hostDocuments } from "./engine";
import { shortcutLabel, useStudio } from "./state/store";

export function App() {
  const { state, dispatch } = useStudio();
  const preset = state.presets.find((item) => item.id === state.selectedPresetId);

  return (
    <div className="desktop" data-theme={state.settings.theme} data-host={state.host}>
      <MenuBar />
      <main
        className="stage"
        onClick={() => (state.menuOpen ? dispatch({ type: "toggle-menu", open: false }) : undefined)}
      >
        <div className="host-switcher" role="tablist" aria-label="Sample host apps">
          {hosts.map((host) => (
            <button
              key={host}
              type="button"
              role="tab"
              aria-selected={state.host === host}
              data-active={state.host === host}
              onClick={() => dispatch({ type: "set-host", host })}
            >
              {hostDocuments[host].title}
            </button>
          ))}
        </div>
        <HostWindow />
        <p className="window-hint">
          Select text, then press {shortcutLabel(state.settings.shortcut)} or use the Tajpo menu.
        </p>
        <aside className="command-strip" aria-label="Studio status">
          <span>{providerTitle(state.settings.provider)}</span>
          <span>{preset?.name ?? "No preset"}</span>
          <span className="capitalize">{state.length}</span>
          <span>{state.settings.theme === "light" ? "Light" : "Dark"}</span>
          <span>{shortcutLabel(state.settings.shortcut)}</span>
        </aside>
        {state.panelOpen ? <InlinePanel /> : null}
        {state.historyOpen ? <HistoryDrawer /> : null}
        {state.settingsOpen ? <SettingsModal /> : null}
        {state.onboardingOpen ? <Onboarding /> : null}
        <Toast />
      </main>
    </div>
  );
}

function providerTitle(provider: string): string {
  if (provider === "demo") return "On-device demo";
  if (provider === "openAI") return "OpenAI";
  return "Local server";
}
