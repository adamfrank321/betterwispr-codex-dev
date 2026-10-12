import AppKit
import BetterWisprCore
import BetterWisprShared

extension AppModel {
    var desktopLibraryStore: DesktopLibraryStore { DesktopLibraryStore(directory: store.directory) }

    func restoreLibraryConnection() {
        do {
            librarySyncState = try desktopLibraryStore.loadSync()
            guard let bookmark = librarySyncState.bookmark else { return }
            var stale = false
            let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI],
                              relativeTo: nil, bookmarkDataIsStale: &stale)
            guard !stale, url.startAccessingSecurityScopedResource() else { throw CocoaError(.fileReadNoPermission) }
            libraryFolder = url
            librarySyncStatus = "Connected"
        } catch { librarySyncStatus = "Reconnect folder"; statusMessage = error.localizedDescription }
    }

    func chooseLibraryFolder() {
        guard !isBusy, meetings.activity == .idle else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.prompt = "Connect library"
        panel.message = "Choose the same shared folder as BetterWispr on your iPhone."
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        guard folder.startAccessingSecurityScopedResource() else {
            librarySyncStatus = "Could not access folder"; return
        }
        do {
            var state = try desktopLibraryStore.loadSync()
            state.bookmark = try folder.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            state.baseline = nil
            try desktopLibraryStore.saveSync(state)
            libraryFolder?.stopAccessingSecurityScopedResource()
            libraryFolder = folder; librarySyncState = state
            Task { await synchronizeLibrary() }
        } catch { folder.stopAccessingSecurityScopedResource(); librarySyncStatus = error.localizedDescription }
    }

    func disconnectLibrary() {
        guard !librarySyncing else { return }
        do {
            var state = try desktopLibraryStore.loadSync()
            state.bookmark = nil; state.baseline = nil
            try desktopLibraryStore.saveSync(state)
            libraryFolder?.stopAccessingSecurityScopedResource()
            libraryFolder = nil; librarySyncState = state; librarySyncStatus = "Sync off"
        } catch { librarySyncStatus = error.localizedDescription }
    }

    private func currentWorkspace() -> SavedState {
        var state = SavedState()
        state.settings = settings; state.history = history; state.vocabulary = vocabulary
        return state
    }

    func synchronizeLibrary() async {
        guard let folder = libraryFolder, storageIsReadable, !isBusy, meetings.activity == .idle else { return }
        librarySyncing = true; meetings.librarySyncing = true
        librarySyncStatus = "Syncing…"
        defer { librarySyncing = false; meetings.librarySyncing = false }
        do {
            // Flush local changes and stop debounce tasks before taking the baseline.
            try persist()
            try meetings.flushForLibrarySync()
            let before = DesktopLibraryStore.snapshot(workspace: currentWorkspace(), meetings: meetings.meetings)
            let merged = try await libraryExchange.exchange(before, baseline: librarySyncState.baseline,
                                                            folder: folder, device: librarySyncState.device)
            let now = currentWorkspace()
            let current = DesktopLibraryStore.snapshot(workspace: now, meetings: meetings.meetings)
            let accepted = LibrarySnapshot.rebasingChanges(from: before, to: current, onto: merged)
            // Local edits made during the exchange stay pending against the remote baseline.
            var sync = librarySyncState; sync.baseline = merged
            let destination = DesktopLibraryStore.applying(accepted, to: now)
            try meetings.flushForLibrarySync()
            try desktopLibraryStore.commit(workspace: destination, meetings: accepted.meetings, sync: sync)
            settings = destination.settings; history = destination.history; vocabulary = destination.vocabulary
            meetings.acceptLibrarySync(accepted.meetings)
            meetings.notesSettings = settings
            librarySyncState = sync
            librarySyncStatus = current == before ? "Updated just now" : "Local changes pending"
        } catch { librarySyncStatus = "Sync needs attention"; statusMessage = error.localizedDescription }
    }
}
