import { HistoryDrawer } from "./components/HistoryDrawer";
import { HostWindow } from "./components/HostWindow";
import { InlinePanel } from "./components/InlinePanel";
import { MenuBar } from "./components/MenuBar";
import { Onboarding } from "./components/Onboarding";
import { SettingsModal } from "./components/SettingsModal";
import { hosts, hostDocuments } from "./engine";
import { shortcutLabel, useStudio } from "./state/store";

export function App() {
  const { state, dispatch } = useStudio();

  return (
    <div className="desktop">
      <MenuBar />
      <main className="stage">
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
        {state.panelOpen ? <InlinePanel /> : null}
        {state.historyOpen ? <HistoryDrawer /> : null}
        {state.settingsOpen ? <SettingsModal /> : null}
        {state.onboardingOpen ? <Onboarding /> : null}
      </main>
    </div>
  );
}
