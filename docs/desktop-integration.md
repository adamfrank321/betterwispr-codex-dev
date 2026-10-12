# Desktop integration

The desktop adapter is generated against upstream `c10b57fd9525216045ab7e9e35d851bacca5cfe7`. It shares the actual Swift package with iOS. No duplicate model or cleanup definitions remain in the generated desktop target.

## Build on Mac

From this repository:

```sh
python3 scripts/prepare_desktop.py
swift build --package-path Desktop/Upstream
swift test --package-path Desktop/Upstream
cd Desktop/Upstream
./scripts/build-app.sh
```

The setup command clones upstream at the pinned commit. Alternatively pass `--source /path/to/pinned/upstream` to use an existing checkout. The generator refuses an existing output directory; choose a fresh `--output` for another build. Changes belong in `Desktop/Overlay` or the generator, not in the disposable generated checkout.

Run the generated desktop app and open Settings → Library sync → Connect. Choose the same parent folder selected in the iOS app. The journal resides at `BetterWisprLibrary/events` beneath it. This requires the patched desktop build; the stock upstream release has no sync controls.

After connection, desktop sync runs every 30 seconds while the app is running and neither dictation nor meeting processing is busy. Sync now triggers it immediately. iOS sync runs on foreground entry, after library edits or on request. File provider delivery may take longer; these timers do not guarantee an iCloud propagation deadline.

## Persistence and recovery

Desktop `LocalStore` continues to own workspace.json. `MeetingStore` continues to own individual meeting files. `DesktopLibraryStore` writes a private, local `library-sync-pending.json` before committing changes across them and `library-sync.json`, which stores the baseline and folder bookmark.

On startup, the adapter replays pending work before either model loads. Normal stores refuse writes until recovery finishes. Replay is repeatable. It validates existing workspace, meeting and metadata files before overwriting them. Malformed or newer-version files stop recovery and remain intact. The pending file is removed only after all destinations and the baseline have been saved.

Local changes made during remote I/O are applied over the merged result and remain pending for the next exchange. API connection settings, selected engines, shortcuts, microphones and other device settings never enter the journal. Synced transcript text is plaintext in the selected folder.

`docs/desktop-design.md` explains ownership. `Desktop/Overlay/Tests/DesktopLibraryTests.swift` exercises the actual desktop AppModel against the same LibraryJournal used by iOS, including deletion propagation and reloading desktop storage. Physical iCloud/bookmark behavior still requires Mac/iPhone acceptance testing.
