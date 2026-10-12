# Desktop sync design

`AppModel.synchronizeLibrary()` takes the current shared snapshot, exchanges it through LibraryJournal on a worker actor, carries forward UI edits made during the exchange, then commits the resulting desktop state. Recording cannot start while an exchange is in progress. Meeting edits remain available and are rebased before commit.

BetterWisprShared owns models, cleanup and event ordering. BetterWisprCore imports it and owns DesktopLibraryStore, which maps shared values onto SavedState and MeetingStore without copying device settings into the journal. AppModel owns connection/status UI and serializes application of results on the main actor.

A local pending transaction contains the full destination workspace, meeting set and sync metadata. The adapter writes this file before touching existing data, replays it idempotently, saves the baseline last and removes it only after all writes succeed. Startup replays it before either desktop model loads. Normal workspace and meeting writes refuse to run while a pending transaction exists. Malformed workspace, meeting or pending files block recovery and remain untouched.

The alternatives were a watcher that edits workspace JSON externally, and migrating all desktop storage into a new monolithic archive. The watcher competes with the existing owners; the archive migration expands this change unnecessarily. A replayable transaction preserves the upstream storage layout and makes interrupted saves testable.

The setup script creates a new checkout from the exact pinned upstream commit, verifies extraction hashes, removes copied model/cleanup definitions, retains the desktop AppSettings extension, adds the local shared dependency and applies adapter hooks. It refuses to overwrite an existing output directory. The input checkout is never edited.

Remaining OS validation is security-scoped bookmarks, iCloud Drive availability and microphone/keyboard behavior on physical devices. Full journal scans are appropriate for this initial implementation; measure large libraries before introducing indexing or compaction.
