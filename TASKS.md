# Task list

Updated 2026-10-12. See docs/verification.md for build evidence.

## Implemented and verified

- [x] Recover prior work, preserve original and publish to the authorized repository.
- [x] Pin upstream and extract shared models/cleanup with Apache-2.0 provenance.
- [x] Implement immutable journal, tombstones, deterministic conflicts and local-edit rebasing.
- [x] Preserve malformed files and pause for incomplete cloud folders.
- [x] Add dictation, history, vocabulary/mode editing, meeting notes/action items/export and settings.
- [x] Add explicit API provider with device-local Keychain storage and redirect rejection.
- [x] Add keyboard insertion and XcodeGen app/keyboard targets.
- [x] Integrate desktop shared package, folder controls, idle polling and replayable persistence.
- [x] Add desktop/mobile journal round-trip and recovery regression coverage.
- [x] Pass source checks, three Python tests, ten shared Swift tests and iOS simulator compilation.
- [x] Pass latest desktop build and all 172 upstream/desktop tests in workflow 38298119747.

## Device and release gates

- [ ] Signed iPhone and Mac acceptance: sync, microphone interruptions, bookmarks, keyboard and API.
- [ ] Assess failed-recording recovery using device results.
- [ ] Signing, app icon, accessibility review, TestFlight and release packaging.

## Later capabilities

- [ ] iOS Whisper/Parakeet adapters, model downloads and memory testing.
- [ ] Longer meeting capture with supported on-device engines.
- [ ] Model-backed Medium cleanup and meeting summaries.
- [ ] UI to export/recover concurrent journal versions and safe journal compaction.
