import { useEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { defaultPresets } from "../engine";
import { defaultSettings, shortcutLabel, useStudio } from "../state/store";

const tabs = ["model", "writing", "shortcut", "appearance", "privacy"] as const;

const focusableSelector =
  'button:not(:disabled), [href], input:not(:disabled), select:not(:disabled), textarea:not(:disabled), [tabindex]:not([tabindex="-1"])';

export function SettingsModal() {
  const { state, dispatch, actions } = useStudio();
  const [tab, setTab] = useState<(typeof tabs)[number]>("model");
  const [presetName, setPresetName] = useState("");
  const [presetPrompt, setPresetPrompt] = useState("");
  const [message, setMessage] = useState("");
  const [testing, setTesting] = useState(false);
  const dialogRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const dialog = dialogRef.current;
    if (!dialog) return;
    const previous = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    dialog.querySelector<HTMLElement>(focusableSelector)?.focus();
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        event.preventDefault();
        event.stopPropagation();
        dispatch({ type: "toggle-settings", open: false });
        return;
      }
      if (event.key !== "Tab") return;
      const items = Array.from(dialog.querySelectorAll<HTMLElement>(focusableSelector)).filter(
        (item) => item.offsetParent !== null,
      );
      if (items.length === 0) return;
      const first = items[0];
      const last = items[items.length - 1];
      const active = document.activeElement;
      if (event.shiftKey && (active === first || !dialog.contains(active))) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && (active === last || !dialog.contains(active))) {
        event.preventDefault();
        first.focus();
      }
    };
    document.addEventListener("keydown", onKeyDown);
    return () => {
      document.removeEventListener("keydown", onKeyDown);
      previous?.focus();
    };
  }, [dispatch]);

  return createPortal(
    <div className="modal-backdrop" onClick={() => dispatch({ type: "toggle-settings", open: false })}>
      <div
        ref={dialogRef}
        className="modal"
        role="dialog"
        aria-modal="true"
        aria-labelledby="settings-title"
        onClick={(event) => event.stopPropagation()}
      >
        <div className="menu-row">
          <h2 id="settings-title" style={{ margin: 0, fontFamily: "var(--serif)" }}>
            Settings
          </h2>
          <button type="button" className="btn-ghost" onClick={() => dispatch({ type: "toggle-settings", open: false })}>
            Close
          </button>
        </div>
        <div className="tabs" role="tablist">
          {tabs.map((item) => (
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
                      baseURL:
                        provider === "openAI"
                          ? "https://api.openai.com/v1"
                          : provider === "localCompatible"
                            ? "http://127.0.0.1:11434/v1"
                            : "",
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
                  Auth
                  <select
                    value={state.settings.authStyle}
                    onChange={(event) =>
                      dispatch({
                        type: "update-settings",
                        settings: { authStyle: event.target.value as typeof state.settings.authStyle },
                      })
                    }
                  >
                    <option value="bearer">Bearer token</option>
                    <option value="apiKeyHeader">api-key header (Azure)</option>
                    <option value="none">No key</option>
                  </select>
                </label>
                <label className="stack">
                  Azure API version
                  <input
                    value={state.settings.apiVersion}
                    placeholder="Leave blank for OpenAI or local /v1"
                    onChange={(event) => dispatch({ type: "update-settings", settings: { apiVersion: event.target.value } })}
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
            <button
              type="button"
              className="btn"
              disabled={testing}
              onClick={async () => {
                setTesting(true);
                const result = await actions.ping();
                setMessage(result);
                setTesting(false);
              }}
            >
              {testing ? "Testing…" : "Test connection"}
            </button>
          </div>
        ) : null}
        {tab === "writing" ? (
          <div className="form-grid">
            <label className="stack">
              Active preset
              <select
                value={state.selectedPresetId}
                onChange={(event) =>
                  dispatch({ type: "set-presets", presets: state.presets, selectedPresetId: event.target.value })
                }
              >
                {state.presets.map((preset) => (
                  <option key={preset.id} value={preset.id}>
                    {preset.name}
                  </option>
                ))}
              </select>
            </label>
            <p className="hint">
              {state.presets.find((item) => item.id === state.selectedPresetId)?.systemPrompt}
            </p>
            <label className="stack" htmlFor="custom-instructions">
              Always-on instructions
              <textarea
                id="custom-instructions"
                value={state.settings.customInstructions}
                placeholder='Example: never use the word utilize. No exclamation marks.'
                onChange={(event) =>
                  dispatch({ type: "update-settings", settings: { customInstructions: event.target.value } })
                }
              />
            </label>
            <p className="hint">
              Applied to every rewrite. The demo engine honors “never use the word …” and “no exclamation”. Remote
              models receive the full note in the system prompt.
            </p>
            <label className="stack">
              New preset name
              <input value={presetName} onChange={(event) => setPresetName(event.target.value)} />
            </label>
            <label className="stack">
              System prompt
              <textarea value={presetPrompt} onChange={(event) => setPresetPrompt(event.target.value)} />
            </label>
            <div className="actions-row">
              <button
                type="button"
                className="btn"
                onClick={() => {
                  if (!presetName.trim() || !presetPrompt.trim()) return;
                  const id = crypto.randomUUID();
                  dispatch({
                    type: "set-presets",
                    presets: [...state.presets, { id, name: presetName.trim(), systemPrompt: presetPrompt.trim() }],
                    selectedPresetId: id,
                  });
                  setPresetName("");
                  setPresetPrompt("");
                  setMessage("Preset added.");
                }}
              >
                Add preset
              </button>
              <button
                type="button"
                className="btn-ghost"
                disabled={state.presets.length <= 1}
                onClick={() => {
                  const next = state.presets.filter((item) => item.id !== state.selectedPresetId);
                  if (next.length === 0) return;
                  dispatch({ type: "set-presets", presets: next, selectedPresetId: next[0].id });
                }}
              >
                Delete selected
              </button>
              <button
                type="button"
                className="btn-ghost"
                onClick={() =>
                  dispatch({ type: "set-presets", presets: defaultPresets, selectedPresetId: defaultPresets[0].id })
                }
              >
                Reset presets
              </button>
            </div>
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
            {(
              [
                ["alt", "Option / Alt"],
                ["shift", "Shift"],
                ["meta", "Command / Meta"],
                ["ctrl", "Control"],
              ] as const
            ).map(([field, label]) => (
              <label key={field}>
                <input
                  type="checkbox"
                  checked={state.settings.shortcut[field]}
                  onChange={(event) =>
                    dispatch({
                      type: "update-settings",
                      settings: { shortcut: { ...state.settings.shortcut, [field]: event.target.checked } },
                    })
                  }
                />{" "}
                {label}
              </label>
            ))}
            <p className="hint">At least one modifier is required so a regular keystroke is not stolen.</p>
          </div>
        ) : null}
        {tab === "appearance" ? (
          <div className="form-grid">
            <label className="stack">
              Theme
              <select
                value={state.settings.theme}
                onChange={(event) =>
                  dispatch({
                    type: "update-settings",
                    settings: { theme: event.target.value as typeof state.settings.theme },
                  })
                }
              >
                <option value="dark">Dark</option>
                <option value="light">Light</option>
              </select>
            </label>
            <p className="hint">The paper window stays light so drafts read like Notes, Mail, Slack, or Pages.</p>
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
    </div>,
    document.body,
  );
}
