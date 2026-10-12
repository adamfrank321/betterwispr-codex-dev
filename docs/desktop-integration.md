# Desktop integration handoff

Inspected at upstream c10b57fd9525216045ab7e9e35d851bacca5cfe7. No desktop adapter has been applied yet.

The current desktop has two persistence owners:

- `Sources/BetterWisprCore/Persistence/LocalStore.swift` reads and writes `workspace.json`, a versioned `SavedState` containing AppSettings, history and vocabulary. `Sources/BetterWispr/App/AppModel.swift` loads it in init and writes through a private `persist()` method. It refuses to overwrite unreadable workspaces.
- `Sources/BetterWisprCore/Persistence/MeetingStore.swift` stores each meeting in its own versioned JSON wrapper. `Sources/BetterWispr/App/MeetingModel.swift` owns meeting changes and scheduled saves. Load returns unreadable file paths, which must block destructive synchronization rather than be interpreted as missing meetings.

Proposed next implementation:

1. Generate a separate desktop checkout pinned to the lock file. Verify original file hashes before applying any patch and fail on revision mismatch.
2. Add a local dependency on BetterWisprShared. Remove the twelve extracted source definitions from BetterWisprCore, retaining the desktop-only AppSettings extension from WritingMode. Import/re-export the shared declarations where needed and run upstream tests to catch visibility assumptions.
3. Persist the journal baseline in the same local transaction as merged workspace state. Meetings need a pending transaction/recovery record because their files and workspace are separate writes. Retrying after a crash must not republish stale records or lose a deletion.
4. Route exchanges through AppModel and MeetingModel on their existing serialized execution path. Wait for scheduled meeting saves, require idle recording state, and preserve device-only AppSettings fields.
5. Offer explicit folder selection, sync status, disconnect and manual refresh. Use the same `BetterWisprLibrary/events` directory as iOS. Never directly edit workspace.json from another process while BetterWispr is running.
6. Add integration tests for existing IDs, first connection, offline changes, remote deletions, unreadable meetings and failed local commits after remote publication.

Do not call desktop synchronization complete until the actual app reads an iOS event and iOS reads a desktop event without losing local preferences or meeting files.
