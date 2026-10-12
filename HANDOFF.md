# Handoff

Updated 2026-10-12. Repository: https://github.com/adamfrank321/betterwispr-codex-dev

## Goal and authorization

Build the native iOS BetterWispr companion with shared desktop models, cleanup and library synchronization. Adam authorized repository writes and continued development, and requested current task and handoff notes. Give brief progress updates and state clearly when work stops. Do not confuse compilation with device acceptance.

## Current state

Source commit `8d91ded82bca18566595a456b3706c3412365a12`, tested through documentation commit `6a10f56f0ae29095732f2f4c0e3c84b77af2ac3a`. See docs/verification.md for the exact CI result.

- iOS SwiftUI app: on-device Apple Speech by default, explicit custom HTTPS API with Keychain credentials, 60-second clips, transcript editing, vocabulary and writing-mode editors, meeting notes/action items/export, usage and settings.
- Keyboard extension inserts saved transcripts from the App Group. It does not record audio or use the network.
- Shared package owns domain models, cleanup and immutable folder journal. Tombstones, deterministic conflicts, edits during sync, malformed data, cloud placeholders and missing previously seen events have regression coverage. Missing files pause sync rather than imply deletion.
- Desktop integration is implemented in Desktop/Overlay and scripts/prepare_desktop.py. It generates an isolated pinned upstream checkout using the shared package. Settings has folder connection and sync controls; idle polling runs every 30 seconds. Device settings stay local.
- Desktop commits workspace, meetings and sync baseline through a replayable pending transaction. Startup recovery precedes model loading; ordinary writes are blocked while recovery is pending. Corrupt files are preserved.
- New editors retain unedited desktop fields and show archive-save failures. Desktop folder selection handles ordinary and security-scoped URLs.

## Sideloading work, 2026-10-12

User authorized preparing an IPA for Signulous. Added scripts/build_device_ipa.py and a dedicated device-ipa workflow. It builds Release iphoneos without signing, checks arm64/iOS Mach-O binaries and both bundles, then uploads the IPA with checksums and entitlement requirements. Device workflow 38315781228 passed at commit cfb8a3bf1f6015443659f2aa3b01b6c96d49790b: 10 Swift tests, 3 Python tests, Release iphoneos build, Mach-O arm64/iOS and ZIP checks. Artifact 11776885191 contains BetterWispr-unsigned.ipa and signing requirements, expires 2026-11-11. IPA SHA-256: 76df9f4b670118be763c0a1ce42b34743b398f40acb289a38aa03d6b2460a90e. Simulator job also passed in run 38315781167; desktop job was still running when this note was written. Device installation remains pending. See docs/sideloading.md. Do not claim Signulous App Group compatibility; it has not been confirmed. No support message sent or account purchase made.

## Verification and next work

Workflow [38298119747](https://github.com/adamfrank321/betterwispr-codex-dev/actions/runs/38298119747) passed both jobs at commit `6a10f56`: full desktop compilation, all 172 upstream/desktop tests (including five desktop integration tests), all 10 shared Swift tests, iOS app/keyboard simulator compilation, source provenance and three portable Python tests. The subsequent handoff update changes documentation only.

Next is signed Mac/iPhone acceptance using docs/testing.md: permissions, interrupted recordings, on-device Speech assets, keyboard Full Access/App Group access, folder bookmark persistence and actual iCloud delivery. No physical-device behavior or signed release has been verified. Signing requires the user's Apple development team and a Mac/device environment; no signing assets are in this repository.

Later scope: iOS Whisper/Parakeet adapters, longer meetings, model-backed Medium cleanup/summaries, conflict-version recovery UI, safe journal compaction, app icon/accessibility review and TestFlight packaging. Do not present these as complete.

## Working instructions

Current checkout: `/workspace/scratch/0b1db2b1299d/BetterWisprMobile`.
Recovered original, untouched: `/workspace/scratch/48ab2e3f8437/BetterWisprMobile`.
Clean pinned upstream: `/workspace/scratch/48ab2e3f8437/upstream`.

The original agent's source had no commits or pushed implementation. This takeover added the application shell, UI, keyboard, project, tests, desktop integration and CI. GitHub main is the durable source; scratch paths may disappear.

Read AGENTS.md, TASKS.md and docs/testing.md. Run `python3 scripts/check_source.py` and `python3 -m unittest discover -s scripts/tests -v`. Linux has no Swift/Xcode; use Apple CI for native builds/tests. Generate desktop into a fresh output directory; never edit the disposable generated checkout. Existing generated scratch checkouts may be stale. Follow docs/desktop-integration.md on Mac.

Upstream is pinned to `c10b57fd9525216045ab7e9e35d851bacca5cfe7`, under Apache-2.0. Ten extracted files are unchanged; WritingMode removes its desktop extension and CorrectionLearner exposes tokenize across modules. Hashes and adaptations are in upstream-lock.json. Do not silently move the pin.

Keep on-device recognition the default, require explicit cloud selection, preserve raw transcripts and unreadable files, and never sync audio, credentials or model assets. Sync text is plaintext in the chosen folder. Stock upstream releases lack this desktop adapter.
