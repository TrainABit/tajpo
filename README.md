# Tajpo

A private native macOS menu bar app: select text anywhere, press a global shortcut, and correct, rewrite, shorten, expand, or change its tone.

**Tajpo Studio** is the same product running in a browser. Use it on Linux or any machine that cannot run the Mac app. It is the local way to finish the idea without deploying anything to a personal Mac.

## Privacy

Tajpo has no account, backend, analytics, or text logging. Text stays on the machine unless you choose a remote provider. The OpenAI (or Azure) key is stored in macOS Keychain on the native app, or in this browser’s localStorage in Studio. The on-device demo engine never leaves the machine.

The Mac app is **not App Sandboxed**. Accessibility, a global hotkey, and clipboard fallback do not work in the sandbox, so distribution is Developer ID + notarization rather than the Mac App Store.

License: MIT. See `LICENSE`.

## Features

- Accessibility selection capture and replacement, with clipboard fallback when AX text is unavailable
- Secure-field rejection, including ancestor/descendant password roles, bullet-only selections, and no clipboard fallback in web areas
- On-device demo engine, OpenAI Chat Completions, Azure-compatible endpoints, and local `/v1` servers
- Correct, improve, rewrite, shorten, tone, expand, simplify, bullets, and continue
- Length control (shorter / same / longer) applied by the demo engine and sent to remote models
- Recordable global shortcut (requires at least one modifier)
- Inline panel with original vs streamed rewrite, optional word diff, token/cost readout, Replace / Copy / Retry / Undo / Redo
- Writing presets, custom instructions, searchable local history, launch at login, Accessibility status, GitHub Releases update check
- First-run onboarding that can finish on the demo engine with no API key

## Run Tajpo Studio (this environment)

Studio is the supported local preview. It does not require Xcode, a Mac, or an API key.

```bash
cd studio
npm install
npm test
npm run dev
```

Open `http://127.0.0.1:5173`. Skip or finish onboarding, select text in the paper window (Notes, Mail, Slack, or Pages), press **⌥⇧T** (Alt+Shift+T), then Replace.

Studio is a finished local workbench, not a screenshot of the Mac app:

- Dark and light desktop themes
- Length controls, writing presets, and always-on custom instructions (the demo engine honors “never use the word …” and “no exclamation”)
- History search, filter, and replay
- Multi-step undo / redo of replacements
- Provider settings with a real Test connection (`GET /models` for remote, instant ready for demo)
- Keyboard: Alt+Shift+T (or your shortcut), 1–9 actions, Ctrl/⌘Enter replace, Esc close, Ctrl/⌘Z undo, Ctrl/⌘Y redo, Ctrl/⌘D diff, Ctrl/⌘, settings

Production-like preview:

```bash
cd studio
npm run build
npm run preview
```

Optional remote model (never required): copy `.env.example` to `studio/.env` and set `VITE_OPENAI_API_KEY`. Studio still defaults to the on-device demo.

End-to-end browser tests, using the machine’s Chrome:

```bash
cd studio
npm run build
npx playwright test
```

## Build the Mac app in Xcode

1. Clone the repository and open `Package.swift`.
2. Select the `Tajpo` scheme and **My Mac**.
3. In **Signing & Capabilities**, choose your Apple Developer Team.
4. Set the target Info tab `LSUIElement` to YES if Xcode generates its own Info.plist. `Sources/Tajpo/Info.plist` is the canonical file used by `scripts/release.sh`.
5. Build and run.
6. Complete onboarding or open Settings: the demo engine works immediately. Save a key or point at a local server when you want a stronger model, then grant Accessibility.

If macOS does not refresh permission after rebuilding, remove the old Tajpo entry under **System Settings > Privacy & Security > Accessibility**, add the current build, and relaunch.

The app targets macOS 14 and Swift 6. Logic lives in the `TajpoCore` library; the `Tajpo` executable is the `@main` entry. Tests import `TajpoCore`.

```bash
swift test
swift build
```

GitHub Actions runs `swift test` / `swift build` on `macos-15` and the Studio unit tests on Ubuntu.

## Local models

In Settings choose **Local server (Ollama, llama.cpp, MLX)** and a `/v1` base URL:

- Ollama: `http://127.0.0.1:11434/v1` after `ollama serve`
- llama.cpp: `http://127.0.0.1:8080/v1` after `llama-server -m model.gguf`
- MLX: `http://127.0.0.1:8080/v1` after `mlx_lm.server`

Auth can be Bearer, Azure `api-key`, or none. The demo engine is the no-server default.

## Release

`scripts/release.sh` builds `dist/Tajpo.app`, writes `AppIcon.icns` on a Mac, and optionally signs and notarizes:

```bash
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
APPLE_ID="you@example.com" TEAM_ID="TEAMID" APP_PASSWORD="app-specific-password" \
./scripts/release.sh
```

Upload the notarized app to GitHub Releases. Tajpo compares `tag_name` to `AppVersion` (`1.2.0`) and offers the release page when a newer tag exists.

## Intentionally out of scope here

- Installing or running the app on a personal MacBook / iCloud / production host
- In-process MLX/llama.cpp weights (use their OpenAI-compatible servers)
- Sparkle and the Mac App Store
- Live Accessibility automation against Notes/Safari/Slack (encoded as `HostAppMatrix`; confirm on a signed Mac build)
