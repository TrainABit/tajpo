import { useState } from "react";
import { defaultPresets } from "../engine";
import { defaultSettings, shortcutLabel, useStudio } from "../state/store";

export function SettingsModal() {
  const { state, dispatch } = useStudio();
  const [tab, setTab] = useState<"model" | "writing" | "shortcut" | "privacy">("model");
  const [presetName, setPresetName] = useState("");
  const [presetPrompt, setPresetPrompt] = useState("");
  const [message, setMessage] = useState("");

  return (
    <div className="modal-backdrop" onClick={() => dispatch({ type: "toggle-settings", open: false })}>
      <div className="modal" role="dialog" aria-labelledby="settings-title" onClick={(event) => event.stopPropagation()}>
        <div className="menu-row">
          <h2 id="settings-title" style={{ margin: 0, fontFamily: "var(--serif)" }}>
            Settings
          </h2>
          <button type="button" className="btn-ghost" onClick={() => dispatch({ type: "toggle-settings", open: false })}>
            Close
          </button>
        </div>
        <div className="tabs" role="tablist">
          {(["model", "writing", "shortcut", "privacy"] as const).map((item) => (
            <button key={item} type="button" role="tab" data-active={tab === item} onClick={() => setTab(item)}>
              {item}
            </button>
          ))}
        </div>
        {tab === "model" ? (
          <div className="form-grid">
            <label className="stack">
              Provider
              <select
                value={state.settings.provider}
                onChange={(event) => {
                  const provider = event.target.value as typeof state.settings.provider;
                  dispatch({
                    type: "update-settings",
                    settings: {
                      provider,
                      model: provider === "demo" ? "tajpo-demo" : provider === "openAI" ? "gpt-4o-mini" : "llama3.2",
                      baseURL: provider === "openAI" ? "https://api.openai.com/v1" : provider === "localCompatible" ? "http://127.0.0.1:11434/v1" : "",
                      authStyle: provider === "openAI" ? "bearer" : "none",
                    },
                  });
                }}
              >
                <option value="demo">On-device demo</option>
                <option value="openAI">OpenAI</option>
                <option value="localCompatible">Local server (Ollama, llama.cpp, MLX)</option>
              </select>
            </label>
            {state.settings.provider !== "demo" ? (
              <>
                <label className="stack">
                  Model
                  <input
                    value={state.settings.model}
                    onChange={(event) => dispatch({ type: "update-settings", settings: { model: event.target.value } })}
                  />
                </label>
                <label className="stack">
                  Base URL
                  <input
                    value={state.settings.baseURL}
                    onChange={(event) => dispatch({ type: "update-settings", settings: { baseURL: event.target.value } })}
                  />
                </label>
                <label className="stack">
                  API key
                  <input
                    type="password"
                    value={state.settings.apiKey}
                    autoComplete="off"
                    onChange={(event) => dispatch({ type: "update-settings", settings: { apiKey: event.target.value } })}
                  />
                </label>
              </>
            ) : (
              <p className="hint">The demo engine stays in this browser. No key, no network.</p>
            )}
            <p className="hint">{message || "Studio never sends keys to a Tajpo backend. There is no Tajpo backend."}</p>
            <button type="button" className="btn-ghost" onClick={() => setMessage("Connection is only required for remote providers.")}>
              Test connection
            </button>
          </div>
        ) : null}
        {tab === "writing" ? (
          <div className="form-grid">
            <label className="stack">
              Active preset
              <select
                value={state.selectedPresetId}
                onChange={(event) => dispatch({ type: "set-presets", presets: state.presets, selectedPresetId: event.target.value })}
              >
                {state.presets.map((preset) => (
                  <option key={preset.id} value={preset.id}>
                    {preset.name}
                  </option>
                ))}
              </select>
            </label>
            <label className="stack">
              Always-on instructions
              <textarea
                value={state.settings.customInstructions}
                onChange={(event) =>
                  dispatch({ type: "update-settings", settings: { customInstructions: event.target.value } })
                }
              />
            </label>
            <label className="stack">
              New preset name
              <input value={presetName} onChange={(event) => setPresetName(event.target.value)} />
            </label>
            <label className="stack">
              System prompt
              <textarea value={presetPrompt} onChange={(event) => setPresetPrompt(event.target.value)} />
            </label>
            <button
              type="button"
              className="btn"
              onClick={() => {
                if (!presetName.trim() || !presetPrompt.trim()) return;
                dispatch({
                  type: "set-presets",
                  presets: [...state.presets, { id: crypto.randomUUID(), name: presetName.trim(), systemPrompt: presetPrompt.trim() }],
                  selectedPresetId: undefined,
                });
                setPresetName("");
                setPresetPrompt("");
              }}
            >
              Add preset
            </button>
            <button
              type="button"
              className="btn-ghost"
              onClick={() => dispatch({ type: "set-presets", presets: defaultPresets, selectedPresetId: defaultPresets[0].id })}
            >
              Reset presets
            </button>
          </div>
        ) : null}
        {tab === "shortcut" ? (
          <div className="form-grid">
            <p>
              Current shortcut: <strong>{shortcutLabel(state.settings.shortcut)}</strong>
            </p>
            <label className="stack">
              Key
              <input
                maxLength={1}
                value={state.settings.shortcut.key}
                onChange={(event) =>
                  dispatch({
                    type: "update-settings",
                    settings: { shortcut: { ...state.settings.shortcut, key: event.target.value.slice(-1) || "t" } },
                  })
                }
              />
            </label>
            <label>
              <input
                type="checkbox"
                checked={state.settings.shortcut.alt}
                onChange={(event) =>
                  dispatch({
                    type: "update-settings",
                    settings: { shortcut: { ...state.settings.shortcut, alt: event.target.checked } },
                  })
                }
              />{" "}
              Option / Alt
            </label>
            <label>
              <input
                type="checkbox"
                checked={state.settings.shortcut.shift}
                onChange={(event) =>
                  dispatch({
                    type: "update-settings",
                    settings: { shortcut: { ...state.settings.shortcut, shift: event.target.checked } },
                  })
                }
              />{" "}
              Shift
            </label>
            <p className="hint">At least one modifier is required so a regular keystroke is not stolen.</p>
          </div>
        ) : null}
        {tab === "privacy" ? (
          <div className="form-grid">
            <p>
              Tajpo has no account or backend. Demo rewrites stay in this tab. History, if enabled, is stored in
              localStorage on this machine. Remote providers receive only the selection you send.
            </p>
            <label>
              <input
                type="checkbox"
                checked={state.settings.historyEnabled}
                onChange={(event) =>
                  dispatch({ type: "update-settings", settings: { historyEnabled: event.target.checked } })
                }
              />{" "}
              Keep a local rewrite history
            </label>
            <button type="button" className="btn-danger" onClick={() => dispatch({ type: "clear-history" })}>
              Clear history
            </button>
            <button
              type="button"
              className="btn-ghost"
              onClick={() => {
                dispatch({ type: "update-settings", settings: defaultSettings });
                setMessage("Settings reset.");
              }}
            >
              Reset settings
            </button>
          </div>
        ) : null}
      </div>
    </div>
  );
}
