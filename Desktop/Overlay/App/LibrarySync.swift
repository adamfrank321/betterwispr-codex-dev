import AppKit
import BetterWisprCore
import BetterWisprShared

extension AppModel {
    var desktopLibraryStore: DesktopLibraryStore { DesktopLibraryStore(directory: store.directory) }

    func startLibraryPolling() {
        libraryPoll = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                guard let self else { return }
                await self.synchronizeLibrary()
            }
        }
    }

    func restoreLibraryConnection() {
        do {
            librarySyncState = try desktopLibraryStore.loadSync()
            guard let bookmark = librarySyncState.bookmark else { return }
            var stale = false
            let options: URL.BookmarkResolutionOptions = librarySyncState.securityScoped == false ? [.withoutUI] : [.withSecurityScope, .withoutUI]
            let url = try URL(resolvingBookmarkData: bookmark, options: options,
                              relativeTo: nil, bookmarkDataIsStale: &stale)
            guard !stale else { throw CocoaError(.fileReadNoPermission) }
            let scoped = url.startAccessingSecurityScopedResource()
            do { _ = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) }
            catch { if scoped { url.stopAccessingSecurityScopedResource() }; throw error }
            libraryFolder = url; libraryFolderScoped = scoped
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
        let scoped = folder.startAccessingSecurityScopedResource()
        do {
            _ = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            var state = try desktopLibraryStore.loadSync()
            state.bookmark = try folder.bookmarkData(options: scoped ? .withSecurityScope : .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
            state.baseline = nil; state.securityScoped = scoped
            try desktopLibraryStore.saveSync(state)
            releaseLibraryFolder()
            libraryFolder = folder; libraryFolderScoped = scoped; librarySyncState = state
            Task { await synchronizeLibrary() }
        } catch { if scoped { folder.stopAccessingSecurityScopedResource() }; librarySyncStatus = error.localizedDescription }
    }

    func disconnectLibrary() {
        guard !librarySyncing else { return }
        do {
            var state = try desktopLibraryStore.loadSync()
            state.bookmark = nil; state.baseline = nil; state.securityScoped = nil
            try desktopLibraryStore.saveSync(state)
            releaseLibraryFolder()
            libraryFolder = nil; librarySyncState = state; librarySyncStatus = "Sync off"
        } catch { librarySyncStatus = error.localizedDescription }
    }

    private func releaseLibraryFolder() {
        if libraryFolderScoped { libraryFolder?.stopAccessingSecurityScopedResource() }
        libraryFolderScoped = false
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
