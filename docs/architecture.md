# Architecture

`Shared` contains upstream Codable value types and cleanup algorithms, plus the mobile dictation pipeline and immutable library journal. iOS owns AVFoundation capture, Apple Speech requests, HTTPS transcription, Keychain, UI and persistence. The keyboard reads a limited transcript snapshot through an App Group and inserts selected text using the host's text document proxy.

Each journal event includes schema version, random event ID, device ID, Lamport counter, record key and optional value. A nil value is a deletion tombstone. Merge selects the highest counter, then device UUID, then event UUID for each key, independent of file enumeration order. Concurrent versions remain in immutable event files but the UI currently shows only the deterministic winner. No conflict recovery UI or compaction exists yet.

The archive stores both local records and the last accepted sync snapshot. Exchange publishes only local changes since that baseline. Initial connection imports local records only where the journal has no existing record or tombstone. Local history remains usable while disconnected. Invalid, unreadable or future-version events stop exchange and preserve all files.

Use one selected folder across devices. iOS keeps a security-scoped bookmark, coordinates file access and retries manually or when returning to the foreground. This is foreground synchronization, not guaranteed continuous background sync. File provider behavior and interrupted writes still need device verification.

No API key, audio file, model weight, microphone setting or desktop shortcut belongs in a shared snapshot. Sync folders contain transcript text in plaintext. Audio clips use temporary files and are deleted after transcription, failure or cancellation. Failed clips are not currently retained for retry.

The desktop bridge imports BetterWisprShared and preserves existing record IDs. The generator integrates journal exchange with AppModel and MeetingModel and adds a replayable transaction across workspace, meetings and the saved sync baseline. See docs/desktop-integration.md and docs/desktop-design.md. The upstream revision stays pinned; CI builds the full patched desktop and runs its tests.
