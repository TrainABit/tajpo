import { shortcutLabel, useStudio } from "../state/store";

const titles = [
  "Write better without leaving your app",
  "A selection, not a chat box",
  "Your shortcut",
  "Your model",
  "Try Tajpo",
];

export function Onboarding() {
  const { state, dispatch } = useStudio();
  const step = state.onboardingStep;
  const last = step === titles.length - 1;

  const continueStep = () => {
    if (last) dispatch({ type: "set-onboarding", open: false });
    else dispatch({ type: "set-onboarding", open: true, step: step + 1 });
  };

  return (
    <div className="onboard-backdrop">
      <div className="onboard" role="dialog" aria-labelledby="onboard-title">
        <div className="dots" aria-hidden="true">
          {titles.map((_, index) => (
            <i key={index} className={index <= step ? "on" : ""} />
          ))}
        </div>
        <h1 id="onboard-title">{titles[step]}</h1>
        {step === 0 ? (
          <p>
            Select text anywhere. Tajpo appears beside it, streams a rewrite, and lets you replace, copy, undo, or redo.
            Studio is the same workflow as the Mac menu bar app, running locally so you can finish the idea without a Mac.
          </p>
        ) : null}
        {step === 1 ? (
          <p>
            The native app uses Accessibility only to read and replace the text you selected. Studio simulates that with
            Notes, Mail, Slack, and Pages drafts. Password-style selections are rejected on the Mac build. Nothing is
            rewritten until you select a passage.
          </p>
        ) : null}
        {step === 2 ? (
          <p>
            Press <strong>{shortcutLabel(state.settings.shortcut)}</strong> after you select text. You can change the
            shortcut in Settings. On Linux, Alt+Shift+T is the Studio default because browser chrome already owns many
            Command combinations. Inside the panel, 1–9 pick an action and Ctrl/⌘Enter replaces.
          </p>
        ) : null}
        {step === 3 ? (
          <div className="form-grid">
            <p>
              Start with the on-device demo. No key, no network. Switch to OpenAI or a local <code>/v1</code> server when
              you want a stronger model. Presets, length, and custom instructions apply to every rewrite.
            </p>
            <label className="stack">
              Provider
              <select
                value={state.settings.provider}
                onChange={(event) =>
                  dispatch({
                    type: "update-settings",
                    settings: { provider: event.target.value as typeof state.settings.provider },
                  })
                }
              >
                <option value="demo">On-device demo</option>
                <option value="openAI">OpenAI</option>
                <option value="localCompatible">Local server</option>
              </select>
            </label>
            <label className="stack">
              Appearance
              <select
                value={state.settings.theme}
                onChange={(event) =>
                  dispatch({
                    type: "update-settings",
                    settings: { theme: event.target.value as typeof state.settings.theme },
                  })
                }
              >
                <option value="dark">Dark desktop</option>
                <option value="light">Light desktop</option>
              </select>
            </label>
          </div>
        ) : null}
        {step === 4 ? (
          <p>
            Select the draft in the paper window, press {shortcutLabel(state.settings.shortcut)}, then Replace. History
            stays on this machine unless you turn it off. Search it, replay an entry, or undo the last few replacements.
          </p>
        ) : null}
        <div className="actions-row">
          {step > 0 ? (
            <button
              type="button"
              className="btn-ghost"
              onClick={() => dispatch({ type: "set-onboarding", open: true, step: step - 1 })}
            >
              Back
            </button>
          ) : null}
          <button type="button" className="btn-ghost" onClick={() => dispatch({ type: "set-onboarding", open: false })}>
            Skip
          </button>
          <button type="button" className="btn" onClick={continueStep}>
            {last ? "Finish" : "Continue"}
          </button>
        </div>
      </div>
    </div>
  );
}
