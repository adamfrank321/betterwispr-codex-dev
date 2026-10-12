# Task list

Updated 2026-10-12. Source completion and runtime verification are separate.

- [x] Recover Sol's uncommitted work and preserve an independent checkout.
- [x] Identify and pin upstream c10b57fd9525216045ab7e9e35d851bacca5cfe7.
- [x] Initialize the user-provided adamfrank321/betterwispr-codex-dev repository.
- [x] Extract shared Swift models and cleanup algorithms with provenance hashes.
- [x] Implement immutable journal, tombstones and deterministic conflict resolution in source.
- [x] Wire dictation, editor, vocabulary, modes, meeting clips, insights and settings screens.
- [x] Wire explicit API provider with Keychain storage and redirect rejection.
- [x] Add keyboard extension for saved transcript insertion.
- [x] Add XcodeGen app/keyboard targets and Apple CI configuration.
- [x] Add Swift regression tests for journal and pipeline behavior.
- [x] Run source integrity check and two portable validator tests successfully.
- [x] Verify seven Swift regression tests and simulator app/keyboard compilation on macOS CI, run 38295003866.
- [ ] Integrate the same shared package and journal with pinned upstream desktop persistence.
- [ ] Test two-device sync, microphone interruption, bookmarks, keyboard and API on physical devices.
- [ ] Finish robust recovery for failed recordings and sync conflicts.
- [x] Add editors for existing vocabulary, modes, meeting notes and action-item completion; simulator compilation pending in this update.
- [ ] Signing, app icon, accessibility review, TestFlight and release packaging.

Release follow-up

- [ ] iOS Whisper/Parakeet adapters, model downloads and memory testing.
- [ ] Longer meeting capture with supported on-device engines.
- [ ] Medium cleanup and meeting summaries with a selected notes model.
- [ ] Export/recover concurrent journal versions and safe journal compaction.

Desktop continuation

- [x] Add pinned, reproducible desktop integration generator and shared-package extraction.
- [x] Implement desktop folder controls, journal exchange and recoverable multi-file commit.
- [x] Add desktop round-trip/recovery tests and Apple CI job.
- [ ] Compile desktop app and pass full upstream plus desktop sync tests on Apple CI.
