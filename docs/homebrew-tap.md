# AgentTalk Homebrew Tap (template)

Homebrew distribution for AgentTalk — a GUI menu-bar app, so this is a
**cask** (not a formula). Users install with:

```bash
brew tap agenttalk/homebrew-tap
brew install --cask agenttalk
```

## How it works

1. `homebrew-tap/agenttalk.rb` — the cask file. Points at a **stable,
   pinned DMG URL** on the GitHub release and a **sha256** of that DMG.
2. When you publish a new release, update the cask's `version`, `sha256`,
   and the download URL, then push to the tap repo.

```ruby
cask "agenttalk" do
  version "0.1.0"
  sha256 "<sha256-of-dmg>"

  url "https://github.com/agenttalk/agenttalk/releases/download/v#{version}/AgentTalk-#{version}-arm64.dmg"
  name "AgentTalk"
  desc "Offline dictation app (Whisper)"
  homepage "https://github.com/agenttalk/agenttalk"

  # First launch downloads the ~1.5 GB Whisper model automatically.
  auto_updates false

  app "AgentTalk.app"

  zap trash: [
    "~/Library/Application Support/AgentTalk",
    "~/Library/Preferences/com.agenttalk.app.plist",
  ]
end
```

## Publishing a new version

```bash
# 1. Build and compute the checksum
./scripts/package.sh
shasum -a 256 dist/AgentTalk-0.1.0-arm64.dmg

# 2. Update this cask (version + sha256 + url), commit, push to the tap repo
# 3. Users: brew update && brew upgrade --cask agenttalk
```

## Alternatives (if you don't want to maintain a tap)

- **Homebrew core**: requires the app to be Developer-ID signed, hosted at a
  stable URL, and passes their audit (no download-from-release-pattern).
  A personal tap is the realistic path for a side project.
- **Direct DMG** (already supported): GitHub Releases + README instructions.

## Notes

- The app itself is unsigned (ad-hoc) until you add Developer ID signing —
  users installing via cask will still hit Gatekeeper. Signing is the
  single biggest quality-of-distribution win.
- The cask is `arm64`-specific in this example. Ship an `x86_64` cask
  variant or a universal DMG for Intel Macs.
