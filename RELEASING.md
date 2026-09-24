# Releasing Tajpo

## One-time setup (maintainer)

1. **Apple Developer Program.** Enroll, then create a **Developer ID Application** certificate. Export it as `.p12`.
2. **Notarization credentials.** Create an App Store Connect API key (Users and Access ▸ Integrations ▸ Team Keys, Developer role). Note the key ID and issuer ID.
3. **`release` Environment secrets.** Create the `release` environment and add these as environment-scoped secrets, not repository secrets:
   - `DEVELOPER_ID_P12_BASE64`: output of `base64 -i cert.p12`
   - `DEVELOPER_ID_P12_PASSWORD`
   - `SIGN_IDENTITY`: e.g. `Developer ID Application: Your Name (TEAMID)`
   - `NOTARY_KEY_P8_BASE64`: output of `base64 -i AuthKey_XXXX.p8`
   - `NOTARY_KEY_ID`
   - `NOTARY_ISSUER`
   The signing job imports the certificate only after the unsigned build job has completed and only signs the downloaded artifact.
4. **Decisions** to make before the first public release:
   - [ ] **License.** Add `LICENSE`, and update `NSHumanReadableCopyright` in `Support/Info.plist` if needed.
   - [ ] **Bundle ID.** `com.trainabit.tajpo` must be a domain you control. Freeze it; changing it later loses users' settings, key and permissions.
   - [ ] **Privacy policy.** Review and approve `PRIVACY.md`.
   - [ ] **Trademark.** Search for "Tajpo" (USPTO, EUIPO, WIPO; classes 9 and 42) and confirm you own the icon.
   - [ ] **Updates.** Sparkle 2, Homebrew only, or manual (see "Updates" below).
   - [ ] **Support channel.** GitHub Issues is wired up in the menu; add an email address if you want one.
5. Protect `main` and require CI to pass. Restrict who can push `v*` tags.

## Every release

1. Update `CHANGELOG.md`. If the default model changed, re-check `ModelCatalog.costHint` against OpenAI's pricing.
2. Resolve the open licensing, privacy, bundle-ID and support decisions above. `scripts/release-preflight.sh` fails closed while `PRIVACY.md` is a draft or the cask still contains a placeholder.
3. Run the manual QA matrix below on at least one Apple Silicon Mac and, ideally, one Intel Mac.
4. Protect `main`, push the release commit, then create and push the tag: `git tag v0.3.0 && git push origin v0.3.0`.
5. Manually dispatch **Release** with that exact tag. The workflow requires the tag to equal the current `origin/main` commit, builds and tests without secrets, signs/notarizes only the downloaded artifact, records the signed DMG checksum in the provenance manifest, and creates a draft release.
6. On a clean Mac (or VM), download the DMG through a browser and open it. Expect only the standard "downloaded from the Internet" prompt.
7. Publish the draft release. Update the Homebrew tap only after its checksum has been verified.

To build a signed release locally instead:

```sh
SIGN_IDENTITY="Developer ID Application: … (TEAMID)" NOTARY_PROFILE=tajpo-notary VERSION=0.3.0 scripts/build-app.sh --dmg
```

(Run `xcrun notarytool store-credentials tajpo-notary` once first.)

## Manual QA matrix

**Pass criteria** for each app: select text → shortcut → an action → **Replace** works, **Copy** works, and your clipboard is restored afterwards.

| Area | Check |
|---|---|
| macOS | 14 Sonoma, 15 Sequoia (15.4+ pasteboard privacy), 26 Tahoe |
| Hardware | Apple Silicon, Intel |
| Accessibility path | TextEdit (plain and rich text), Notes, Mail compose, Pages |
| Web | Safari and Chrome: a textarea and Gmail compose; Firefox |
| Clipboard path | Slack, VS Code, Discord, Microsoft Word |
| Copy only | Terminal and iTerm2 (no Replace); read-only web text and PDFs |
| Refused | password fields |
| Keyboard layouts | U.S., German, French, Dvorak, Dvorak–QWERTY ⌘, Russian |
| Environment | multiple displays, a full-screen app, Stage Manager, light and dark mode, VoiceOver, Increase Contrast, a clipboard manager (Maccy/Raycast) |
| Providers | valid key; invalid key; no credit; gpt-5-mini; Ollama; offline |
| Lifecycle | first launch from the DMG (safe Finder handoff); launch at login on/off; updating over an existing install keeps permission and key |

Also run the Appendix D checks in `AUDIT.md`.

## Updates

Tajpo currently checks GitHub Releases and opens the release page; it does not silently replace the app. The check is opt-in or manual and the Privacy Policy explains the request. Sparkle can be added later as a separate reviewed change.

## Crash reports

- **No crash service.** There is no telemetry. macOS writes `.ips` crash reports to `~/Library/Logs/DiagnosticReports`.
- **User reports.** The issue template asks users to attach those reports.
- **Symbolication.** Keep each release's `Tajpo-<version>.dSYM.zip`; you need it to symbolicate crash reports.
