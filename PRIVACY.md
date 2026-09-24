# Tajpo Privacy Policy

_Last updated: 2026-09-22. Draft; the maintainer must review it before public release._

Tajpo is a macOS app that edits text you select. It has no servers, no accounts, no analytics, and no crash reporting service. The developer never receives your text, your API key, or information about how you use the app.

## What Tajpo sends, and to whom

- **The text you select, only when you choose an action** (Correct, Improve, a custom instruction, and so on), together with the instructions for that action. It goes directly from your Mac to the AI server set in Settings ▸ AI Provider:
  - **OpenAI (default).** You use your own OpenAI API key and are OpenAI's customer. OpenAI's own terms and privacy policy apply to that data. See [how OpenAI handles API data](https://platform.openai.com/docs/guides/your-data).
  - **Another server you configure**, for example Ollama or LM Studio running on your Mac. Text then goes only to that server. The OpenAI key is not loaded or sent to a custom server.
- **Update checks.** If you turn on weekly update checks, or choose Check for Updates… in the menu, Tajpo asks GitHub's public API for the latest release number of Tajpo. The request contains the product name and app version for protocol compatibility, but not your text or key; GitHub still receives ordinary network metadata such as your IP address.
- **Nothing else is sent.** Opening the panel sends nothing. Demo scenes are offline. The only optional background request is the update check described above.

## What Tajpo stores on your Mac

- **Your API key**, in the macOS Keychain.
- **Settings and history**: settings, shortcuts, style presets, recent custom instructions, and a count of your edits for the last 7 days. These are kept in Tajpo's preferences file and never leave your Mac.
- **Nothing else.** Tajpo does not keep copies of your text or of results.

## Permissions

- **Accessibility.** Tajpo uses this to read the text you select and to put the result back, only when you press Tajpo's shortcut or use its menu. It does not record keystrokes, read your screen, or read other windows, and it refuses to read password fields.
- **Clipboard.** Some apps don't support Accessibility. There, Tajpo briefly uses the clipboard to copy the selected text, then restores what you had. The temporary copy is marked for clipboard managers; the original item was created by the source app, so a clipboard manager may see that brief copy before Tajpo can mark it.

## Contact

Questions: open an issue at https://github.com/TrainABit/tajpo/issues.
