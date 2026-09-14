# Tajpo

A private, native macOS writing tool. Select text anywhere, press a global hotkey, and Tajpo improves or rewrites it in place.

## Privacy promise

- No Tajpo account and no Tajpo backend are required for the MVP.
- Text stays on the Mac except for the API request made directly to the provider chosen by the user.
- The OpenAI API key is BYOK and stored in Keychain.
- A local provider (MLX or llama.cpp) can implement the same LLM client interface later.
- No analytics or text logging by default.

## MVP scope

1. Menu bar app and settings.
2. User-configurable global hotkey.
3. Read selected text through macOS Accessibility APIs.
4. Rewrite through the user's OpenAI API key.
5. Replace the selection while preserving the clipboard where possible.
6. Clear permission, error, and progress states.

## Architecture

The starter is a Swift 6 / macOS 14 package. It separates app composition, hotkey handling, text selection, provider-neutral LLM access, Keychain storage, and settings. That keeps a future local MLX or llama.cpp provider independent from the rewrite feature.

The complete starter source is in `tajpo-source.zip` in this repository. Extract it locally to preserve its directory structure (`Sources/Tajpo/...`, `Tests/...`, `Package.swift`).

## Next

Make Accessibility-based replacement robust, add editable shortcut recording, test the OpenAI Responses integration, and add permission/error UX.
