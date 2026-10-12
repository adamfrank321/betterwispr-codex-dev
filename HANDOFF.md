# Handoff

## Goal and authorization

Build an iOS variation of BetterWispr, sharing desktop functionality and synchronizing libraries. Adam authorized repo writes and asked for continuously updated TASKS.md and HANDOFF.md. On October 12 he stopped the previous agent and asked this thread to continue development rather than spend time diagnosing stalls.

## Recovered state

Sol's source was at `/workspace/scratch/48ab2e3f8437/BetterWisprMobile`, with no local commits and nothing pushed. It contained shared domain/cleanup files, Library.swift, AppModel.swift, DictationRecorder.swift and CloudTranscriber.swift. No views, keyboard target, project configuration or tests existed. Its handoff incorrectly still said no repo existed after Adam supplied one.

Current working root: `/workspace/scratch/0b1db2b1299d/BetterWisprMobile`.
Upstream reference checkout: `/workspace/scratch/48ab2e3f8437/upstream`.
Repository: https://github.com/adamfrank321/betterwispr-codex-dev . GitHub access verified with push permission. Initialized default main branch through the connector.

## Implemented in this takeover

Added SwiftUI entry point and screens, keyboard insertion, XcodeGen target/entitlement specification, seven shared Swift tests, provenance validation, two Python validator tests and macOS CI. Added a 90-second Speech timeout and reduced recording clips to 60 seconds. App foreground refresh triggers sync; entering the background stops active capture. No continuous background recording is claimed.

## Verification

Linux has no Swift compiler or Xcode. Source integrity check and two Python tests passed on October 12. Swift tests and the simulator build are pending macOS CI. None of the microphone, recognition, iCloud folder or keyboard behavior has been device-tested. Do not equate source implementation with a working signed app.

## Resume, in order

1. Inspect GitHub Actions for the latest main commit. Fix compile/test failures and record exact results here.
2. Finish desktop integration using the pinned upstream workspace persistence, not competing JSON file watchers. See docs/architecture.md.
3. Run the physical-device acceptance checklist in docs/testing.md. Improve capture interruption/failure recovery before long recordings.
4. Complete editing controls for existing modes, vocabulary and meeting notes. Add conflict recovery before journal compaction.

## Preserved decisions

- Native SwiftUI app, Foundation shared package; upstream MIT license retained.
- Default speech recognition is explicitly on-device. Cloud upload requires selecting Custom API.
- Sync history, vocabulary, modes, meetings and writing preferences through immutable event files. Never sync credentials, recordings or model assets.
- Preserve raw transcripts and unreadable files. Retain tombstones and concurrent event versions.
- Keyboard inserts saved text; microphone access is unavailable to keyboard extensions.
- Desktop integration, Whisper/Parakeet for iOS, full meetings and Medium cleanup remain unfinished.

## Sources

- https://github.com/opennookorg/betterwispr at c10b57fd9525216045ab7e9e35d851bacca5cfe7
- https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html
- https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard
- https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md
