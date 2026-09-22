# Tajpo Privacy Policy

_Last updated: 2026-09-22. Draft; the maintainer must review it before public release._

Tajpo is a macOS app that edits text you select. It has no servers, no accounts, no analytics, and no crash reporting service. The developer never receives your text, your API key, or information about how you use the app.

## What Tajpo sends, and to whom

- **The text you select, only when you choose an action** (Correct, Improve, a custom instruction, and so on), together with the instructions for that action. It goes directly from your Mac to the AI server set in Settings ▸ AI Provider:
  - **OpenAI (default).** You use your own OpenAI API key and are OpenAI's customer. OpenAI's own terms and privacy policy apply to that data. See [how OpenAI handles API data](https://platform.openai.com/docs/guides/your-data).
  - **Another server you configure**, for example Ollama or LM Studio running on your Mac. Text then goes only to that server.
- **Nothing is sent** when you only open the panel, and nothing is sent in the background.

## What Tajpo stores on your Mac

- **Your API key**, in the macOS Keychain.
- **Settings and history**: settings, shortcuts, style presets, recent custom instructions, and a count of your edits for the last 7 days. These are kept in Tajpo's preferences file and never leave your Mac.
- **Nothing else.** Tajpo does not keep copies of your text or of results.

## Permissions

- **Accessibility.** Tajpo uses this to read the text you select and to put the result back, only when you press Tajpo's shortcut or use its menu. It does not record keystrokes, read your screen, or read other windows, and it refuses to read password fields.
- **Clipboard.** Some apps don't support Accessibility. There, Tajpo briefly uses the clipboard to copy the selection or paste the result, then restores what you had. Tajpo marks these temporary items so clipboard managers skip them.

## Contact

Questions: open an issue at https://github.com/TrainABit/tajpo/issues.
