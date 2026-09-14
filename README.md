# Tajpo

A private native macOS menu bar app: select text anywhere, press a global shortcut, and correct, rewrite, shorten, or change its tone.

## Privacy

Tajpo has no account, backend, analytics, or text logging. Text stays on the Mac unless you choose a remote provider. The OpenAI (or Azure) key is stored in macOS Keychain. A local Ollama, llama.cpp, or MLX OpenAI-compatible server uses the same client boundary and keeps text on-device.

The app is **not App Sandboxed**. Accessibility, a global hotkey, and clipboard fallback do not work in the sandbox, so distribution is Developer ID + notarization rather than the Mac App Store.

License: MIT. See `LICENSE`.

## Features

- Accessibility selection capture and replacement, with clipboard fallback when AX text is unavailable
- Secure-field rejection, including ancestor/descendant password roles, bullet-only selections, and no clipboard fallback in web areas
- OpenAI Chat Completions, Azure-compatible endpoints, and local `/v1` servers
- Correct, improve, rewrite, shorten, and tone actions
- Recordable global shortcut (requires at least one modifier)
- Inline panel with original vs streamed rewrite, token/cost readout, Replace / Copy / Retry / Undo
- Writing presets, launch at login, Accessibility status, GitHub Releases update check
- First-run onboarding that waits for Accessibility, the shortcut, and a key or local provider

## Build in Xcode

1. Clone the repository and open `Package.swift`.
2. Select the `Tajpo` scheme and **My Mac**.
3. In **Signing & Capabilities**, choose your Apple Developer Team.
4. Set the target Info tab `LSUIElement` to YES if Xcode generates its own Info.plist. `Sources/Tajpo/Info.plist` is the canonical file used by `scripts/release.sh`.
5. Build and run.
6. Complete onboarding or open Settings: save a key or point at a local server, then grant Accessibility.

If macOS does not refresh permission after rebuilding, remove the old Tajpo entry under **System Settings > Privacy & Security > Accessibility**, add the current build, and relaunch.

The app targets macOS 14 and Swift 6. Logic lives in the `TajpoCore` library; the `Tajpo` executable is the `@main` entry. Tests import `TajpoCore`.

## Local models

In Settings choose **Local server (Ollama, llama.cpp, MLX)** and a `/v1` base URL:

- Ollama: `http://127.0.0.1:11434/v1` after `ollama serve`
- llama.cpp: `http://127.0.0.1:8080/v1` after `llama-server -m model.gguf`
- MLX: `http://127.0.0.1:8080/v1` after `mlx_lm.server`

Auth can be Bearer, Azure `api-key`, or none.

## Release

`scripts/release.sh` builds `dist/Tajpo.app`, writes `AppIcon.icns` on a Mac, and optionally signs and notarizes:

```bash
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
APPLE_ID="you@example.com" TEAM_ID="TEAMID" APP_PASSWORD="app-specific-password" \
./scripts/release.sh
```

Upload the notarized app to GitHub Releases. Tajpo compares `tag_name` to `AppVersion` (`1.1.0`) and offers the release page when a newer tag exists.

## Tests

On a Mac:

```bash
swift test
swift build
```

GitHub Actions runs the same commands on `macos-15`. Host-app Accessibility behavior is encoded as a decision matrix in `HostAppMatrix` (Notes, Safari, Chrome, Slack, VS Code, Electron, secure fields). Live AX automation across those apps still requires a signed Mac build and manual confirmation.
