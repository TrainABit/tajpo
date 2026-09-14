# Tajpo

A private native macOS menu bar app: select text anywhere, press a global shortcut, and improve, rewrite, shorten, or change its tone.

## Privacy

Tajpo has no account, backend, analytics, or text logging. Text stays on the Mac except for direct calls from the app to OpenAI using the user's own API key. The key is stored in macOS Keychain. A local MLX/llama.cpp provider is planned behind the same client boundary.

## MVP

- Accessibility API selection capture and replacement
- Clipboard fallback with clipboard backup/restore
- Accessibility permission prompt and actionable errors
- OpenAI Chat Completions (`gpt-4o-mini` default, configurable)
- Improve, rewrite, shorten, and tone actions
- Configurable key and modifiers for the global Carbon hotkey
- Menu bar progress, status, and error feedback
- Clear missing-key, network, API, empty-response, and rate-limit errors

## Build in Xcode

1. Clone or download the repository.
2. In Xcode choose **File > Open** and select `Package.swift`.
3. Select the `Tajpo` scheme and **My Mac** destination.
4. In **Signing & Capabilities**, choose your Apple Developer Team if Xcode requests signing.
5. Build and run.
6. Open Tajpo Settings, save an OpenAI API key, then request Accessibility access.
7. If macOS does not refresh permission immediately after rebuilding, remove the old Tajpo entry under **System Settings > Privacy & Security > Accessibility**, add/enable the current build, and relaunch.

The app targets macOS 14 and Swift 6. Because this environment cannot run Xcode/macOS frameworks, the first Xcode build may reveal a small SDK/compiler adjustment.

## Next

Local MLX/llama.cpp inference, signed/notarized distribution, richer shortcut recording, streaming UI, and tests for Accessibility behavior across host apps are deliberately outside this first MVP.

## Streaming and safety

OpenAI responses stream over the Chat Completions SSE connection. The menu shows received character progress while the model writes. Tajpo rejects secure/password fields, empty selections, and selections above 100,000 characters. Clipboard fallback restores all pasteboard item data after copying or pasting.

## Inline workflow

Select text and press the global shortcut. Tajpo reads the AX selection bounds and opens a floating SwiftUI-backed `NSPanel` beside the cursor. Choose Correct, Improve, Rewrite, Shorten, or Tone. Output streams in the panel, then Replace, Copy, or Retry. The menu bar remains a lightweight status/settings hub.

Writing presets include Professional and Casual, with custom name + system prompt creation in Settings. All action prompts pass through the separately testable `PromptBuilder.antiSlop` rules. Correction intentionally changes only grammar, spelling, and punctuation.

First launch opens a five-step onboarding window: product explanation, just-in-time Accessibility rationale/request, shortcut exercise, Keychain API-key setup, and a practice field.
