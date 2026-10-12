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

Linux has no Swift compiler or Xcode. Source integrity check and two Python tests passed on October 12. At commit `1ce2d869dd61cfb73de08ebefc68f6ce74d9a25a`, all seven Swift tests, XcodeGen generation and the simulator app/keyboard build passed in GitHub Actions run https://github.com/adamfrank321/betterwispr-codex-dev/actions/runs/38295003866 . The follow-up makes audio-session deactivation best-effort after recording has safely stopped, so a deactivation error cannot strand its temporary file; its new CI run should also be checked. None of the microphone, recognition, iCloud folder or keyboard behavior has been device-tested. Do not equate source implementation with a working signed app.

## Resume, in order

1. Inspect GitHub Actions for the latest main commit. The first full Apple build is green; keep that gate green as development continues.
2. Finish desktop integration using the pinned upstream workspace persistence, not competing JSON file watchers. See docs/architecture.md and docs/desktop-integration.md for the inspected persistence entry points.
3. Run the physical-device acceptance checklist in docs/testing.md. Improve capture interruption/failure recovery before long recordings.
4. Complete editing controls for existing modes, vocabulary and meeting notes. Add conflict recovery before journal compaction.

## Preserved decisions

- Native SwiftUI app, Foundation shared package; upstream Apache-2.0 license retained.
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

## Desktop integration work, October 12 continuation

Added `scripts/prepare_desktop.py` and `Desktop/Overlay`. The generator creates an isolated checkout at the pinned revision, replaces the duplicated models/cleanup with BetterWisprShared, and adds the desktop journal adapter and Settings controls. Original upstream checkout is untouched. DesktopLibraryStore stages a replayable local transaction before applying workspace, meeting and baseline updates. Startup recovers before loading either model; normal stores refuse writes during pending recovery. Added five desktop tests, including an AppModel-to-mobile-journal round trip, and a shared rebase regression test. Apple CI now includes desktop build and full upstream tests. Source validation and three portable tests pass; new Apple jobs are pending at this checkpoint.

Desktop CI run 38296642425 passed iOS/shared verification but the desktop build found CorrectionLearner.tokenize inaccessible across the new module boundary. The method is now public with the extraction adaptation recorded in upstream-lock.json; its algorithm is unchanged. Also added automatic idle desktop polling and journal guards for cloud placeholders and previously synchronized keys whose files are missing. New shared tests cover both incomplete-folder cases.
