# Draft cask for a TrainABit/homebrew-tap repository. Requires a Developer ID
# signed and notarized DMG attached to a GitHub Release.
# After each release, update `version` and `sha256` (from Tajpo-<version>.dmg.sha256).
cask "tajpo" do
  version "0.3.0"
  sha256 "REPLACE_WITH_DMG_SHA256"

  url "https://github.com/TrainABit/tajpo/releases/download/v#{version}/Tajpo-#{version}.dmg"
  name "Tajpo"
  desc "Improve selected text in any app with a keyboard shortcut"
  homepage "https://github.com/TrainABit/tajpo"

  depends_on macos: ">= :sonoma"

  app "Tajpo.app"

  uninstall quit: "com.trainabit.tajpo"

  zap trash: [
    "~/Library/Preferences/com.trainabit.tajpo.plist",
  ]

  caveats <<~EOS
    Tajpo stores your API key in the macOS Keychain (item "Tajpo OpenAI API key")
    and needs Accessibility access. After uninstalling, remove those manually:
      tccutil reset Accessibility com.trainabit.tajpo
  EOS
end
