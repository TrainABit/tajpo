# Changelog

## Unreleased (0.3.0)

### Added
- **Custom instructions.** Type what you want in the panel ("make it a bullet list", "translate to English") or press ⌘6. Recent instructions are remembered, and Repeat reruns the last one.
- **New setup guide.** You now see Tajpo work before you're asked for any permission. The guide adds a cost explanation, a numbered API-key checklist, a local-model option, a clear explanation of what Accessibility access allows, and automatic detection once access is granted.
- Menu: "Finish setup" shortcuts, a reminder of your shortcut, and a weekly edit count. **Report a Problem** opens a pre-filled GitHub issue.
- Occasional one-time tips after you've used Tajpo a few times.
- Tajpo now hands temporary launches to Finder for a normal drag-to-Applications install; it no longer copies or weakens Gatekeeper state itself.
- Release workflow: a manually dispatched, tag-validated workflow builds unsigned, signs/notarizes only the fixed artifact, and creates a draft release with the DMG, portable SHA-256 checksum, manifest, and dSYM.

### Changed
- **Panel.**
  - A clear full-panel message when nothing is selected.
  - A placeholder while the result starts, and auto-scroll while it streams.
  - Shortcuts shown on the buttons, and the chosen action marked.
  - Copy becomes the main button where text can't be replaced.
  - Esc stops a running request before it closes the panel.
  - VoiceOver announcements, and a change view that doesn't rely on color alone.
- **Settings.** Native toolbar tabs, a provider picker (OpenAI or another server), shortcut recorders with a clear button and a live preview, and presets marked Active.
- Friendlier error messages that say what to do next.
- ⌘W and ⌘M work in Tajpo's windows.
- Launch at login handles macOS asking for approval in System Settings.

### Fixed
- A shortcut you turned off came back after relaunch.
- Replace could report success before the target app had applied the paste; it now checks that the text actually changed.
- Leaving the shortcut recorder without pressing a key left Tajpo's shortcuts paused.
- A panel closing after Replace could close a newer panel opened in the meantime.
- API keys and project IDs are no longer loaded or forwarded to custom OpenAI-compatible servers; new keys are tested before replacing an existing key.
- Replace now fails closed when the frontmost app or original selection cannot be verified, and cancels side effects when a session closes.
- Empty/unknown/incomplete model output can no longer enable Replace; Shorten output is bounded and streams are size-limited.
- Clipboard fallback targets are revalidated, rich/terminal content is copy-only when it cannot be verified, and clipboard restore no longer silently drops unavailable representations.
- Demo scenes are strictly offline, onboarding preserves existing preferences, and failed update checks no longer suppress retries for a week.
- The install script now stages and verifies signed bundles without deleting the existing app first.
- The release checksum is portable and the CI/snapshot/E2E scripts fail closed.

## 0.2.0

Complete overhaul after the full audit (see AUDIT.md): the app builds, replacements are safe, prompts are consistent, setup is rebuilt, and packaging exists.
