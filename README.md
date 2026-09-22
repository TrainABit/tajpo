# Tajpo

A private macOS menu bar app: select text in any app, press a shortcut, and correct, improve, rewrite, shorten, or change its tone. You check the result next to your text, then replace or copy it.

## Requirements

- macOS 14 Sonoma or later
- An OpenAI API key **with prepaid credit** ([create a key](https://platform.openai.com/api-keys), [add credit](https://platform.openai.com/settings/organization/billing/overview)). API usage is billed separately from ChatGPT subscriptions. Or any OpenAI-compatible server, such as Ollama or LM Studio, which needs no key.
- To build: Xcode 16 or later (Swift 6)

## Install

Build a signed app bundle and copy it to /Applications:

```sh
git clone https://github.com/TrainABit/tajpo.git
cd tajpo
scripts/build-app.sh --install
```

On first launch Tajpo opens a short setup guide. It covers Accessibility access, your shortcut (default **⌃⌥T**), your API key, and a practice run.

### Keep permissions across rebuilds

macOS ties the Accessibility permission to the app's code signature. The default ad hoc signature changes on every build, so macOS forgets the permission each time. You'll see Tajpo switched on in System Settings but still get "Tajpo needs Accessibility access". Sign with a stable identity to avoid this:

1. Open **Keychain Access ▸ Certificate Assistant ▸ Create a Certificate…**
2. Name it `Tajpo Dev`. Set Identity Type to **Self Signed Root** and Certificate Type to **Code Signing**. Click Create.
3. Build with `SIGN_IDENTITY="Tajpo Dev" scripts/build-app.sh --install`

If you have an Apple Developer account, use your Developer ID identity. You can also notarize and create a DMG:

```sh
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE=your-notarytool-profile \
scripts/build-app.sh --dmg
```

## Use

1. Select text in any app.
2. Press **⌃⌥T**. A panel opens next to the selection and shows the text Tajpo read.
3. Choose **Correct**, **Improve**, **Rewrite**, **Shorten** (⌘1–⌘4) or **Tone** (⌘5; the arrow picks a tone). The result streams in.
4. Press **Replace** (⌘↩) or **Copy** (⇧⌘C). **Retry** is ⌘R, and ⎋ closes the panel.

**⌃⌥R** repeats your last action on a new selection. Correct shows its changes as a word-level diff; other actions can show one too. Where text can't be edited (web pages, PDFs, terminals), Tajpo offers Copy instead of Replace.

**Style presets** add your own instructions, such as "Use British spelling", to Improve, Rewrite, Shorten and Change Tone. Correct never uses presets, and a chosen tone overrides a preset. Pick the active preset from the menu bar, the panel, or Settings.

## How it works

- **Reading the selection.** Tajpo reads it through the Accessibility API. Apps that don't support that (some Electron and cross-platform apps) are handled with a synthetic ⌘C. The clipboard is restored afterwards, and temporary items are marked so clipboard managers ignore them.
- **Replacing text.** Replace writes through Accessibility when possible and checks the result. Otherwise it pastes with ⌘V into the original app, but only if that app is still in front and the same text is still selected. If not, it tells you instead of pasting somewhere else.
- **Streaming.** The OpenAI Chat Completions response streams in. If the model stops because of its length limit or a content filter, Replace is disabled so your text is never swapped for a cut-off version.
- **What gets sent.** The selected text goes to the model inside delimiters, with instructions to edit it rather than reply to it.

## Privacy

- **What leaves your Mac.** Text leaves only when you choose an action. It goes directly to the server set under **Settings ▸ AI Provider**, which is OpenAI by default, using your own key.
- **What Tajpo doesn't have.** There is no backend, no account, no analytics, and no text logging.
- **Where things are stored.** The API key lives in the macOS Keychain.
- **Password fields.** Tajpo refuses to read secure and password fields.

## Settings

Open **Settings…** from the menu bar icon:

- **General:** the two shortcuts (click to record), Accessibility status, and launch at login.
- **AI Provider:** API key status and Test Connection, the model (default `gpt-4.1-mini`), and the server URL for OpenAI-compatible servers such as Ollama (`http://localhost:11434/v1`).
- **Style Presets:** create, edit, delete, and restore presets.
- **Privacy:** what is sent where.

## Troubleshooting

| Problem | Fix |
|---|---|
| "Tajpo needs Accessibility access" although it's switched on | The permission belongs to an older build. In **System Settings ▸ Privacy & Security ▸ Accessibility**, select Tajpo, remove it with −, add it again, and use a stable signing identity (see above). `tccutil reset Accessibility com.trainabit.tajpo` also clears it. |
| The shortcut does nothing | Check the menu bar menu for a ⚠︎ warning. Another app may use the same shortcut; record a different one in Settings. Shortcuts pause while another app has secure keyboard entry on, e.g. a focused password field. |
| "No API credit" | Add credit to your OpenAI account; the API doesn't use your ChatGPT subscription. |
| Replace says the selection changed | You clicked elsewhere while the result was being written. Select the text again, or use Copy. |
| A model is rejected | Use **Test Connection** in Settings. Some models aren't available to every account. |

## Development

```sh
swift build          # builds TajpoCore and the app (macOS)
swift test           # runs the TajpoCore tests (macOS or Linux)
swift run Tajpo      # runs the app without a bundle
```

`swift run` and running from Xcode start the app without a bundle. macOS then attributes the Accessibility permission to Terminal or Xcode, and launch at login is unavailable. Use `scripts/build-app.sh` for real use.

The code has two layers:

- **`Sources/TajpoCore`:** platform-independent logic, covered by tests: prompts, streaming parser, error mapping, validation, output cleanup, diff, shortcut rules, panel placement.
- **`Sources/Tajpo`:** the macOS app: Accessibility and clipboard, Carbon hotkeys, Keychain, and SwiftUI/AppKit UI.

CI builds and tests on macOS and Linux and produces an ad hoc signed DMG.
