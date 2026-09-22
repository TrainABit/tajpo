# Changelog

## Unreleased (0.3.0)

### Added
- **Custom instructions.** Type what you want in the panel ("make it a bullet list", "translate to English") or press ⌘6. Recent instructions are remembered, and Repeat reruns the last one.
- **New setup guide.** You now see Tajpo work before you're asked for any permission. The guide adds a cost explanation, a numbered API-key checklist, a local-model option, a clear explanation of what Accessibility access allows, and automatic detection once access is granted.
- Menu: "Finish setup" shortcuts, a reminder of your shortcut, and a weekly edit count. **Report a Problem** opens a pre-filled GitHub issue.
- Occasional one-time tips after you've used Tajpo a few times.
- Tajpo offers to move itself to Applications when opened from a disk image.
- Release workflow: builds a signed, notarized DMG plus dSYM when a version tag is pushed.

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
- "Move to Applications" copied the quarantine flag, so macOS moved the app to a temporary location again; Tajpo now quits only after the new copy opens.
- The clipboard is restored only when nothing else changed it in the meantime.
- Keychain read errors are shown instead of looking like a missing key.

## 0.2.0

Complete overhaul after the full audit (see AUDIT.md): the app builds, replacements are safe, prompts are consistent, setup is rebuilt, and packaging exists.
