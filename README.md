# BetterWispr iOS

Native SwiftUI companion to [BetterWispr](https://github.com/opennookorg/betterwispr), with a shared Swift package for transcript models, vocabulary, writing modes, cleanup and library synchronization.

Early development build. Native compilation and physical-device verification are tracked in [HANDOFF.md](HANDOFF.md), not implied by source completion.

## Current implementation

- On-device Apple speech recognition by default; explicitly selected HTTPS transcription API with device-local Keychain credentials.
- Record clips up to 60 seconds; edit saved transcripts while preserving raw recognition; learn vocabulary corrections.
- History, vocabulary, writing modes, meeting clip export and usage totals.
- Folder-based event journal for history, vocabulary, modes, meetings and preferences. Credentials, recordings and model files are excluded.
- Keyboard extension inserts recent saved transcripts. Record in the main app, then return to the destination app and select the keyboard. Full Access is required for the shared container; the keyboard does not access the network.

Desktop synchronization requires the desktop adapter, which is not implemented yet. Do not point this journal at upstream workspace JSON files. Whisper/Parakeet on iOS, long meeting capture and Medium cleanup are follow-up work.

## Build

Use a Mac with Xcode 26 or later and Swift 6.2 or later:

```sh
brew install xcodegen
swift test --package-path Shared
xcodegen generate
xcodebuild -project BetterWispr.xcodeproj -scheme BetterWispr \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

For a device build, choose your development team and register the app/keyboard bundle IDs and App Group from `project.yml`, or replace them with your own. Both targets must share the same group. Generated project, plists and entitlements are recreated by XcodeGen.

## Development

Read [TASKS.md](TASKS.md), [HANDOFF.md](HANDOFF.md) and [docs/testing.md](docs/testing.md). Run `python3 scripts/check_source.py` and `python3 -m unittest discover -s scripts/tests -v` on any host. The Apple workflow runs actual Swift tests and builds the app plus keyboard.

Upstream source is pinned in `upstream-lock.json`. Copied files retain the upstream MIT license in `LICENSE`; eleven files are unchanged and WritingMode removes the desktop settings extension. The source validator detects drift from this extracted baseline.
