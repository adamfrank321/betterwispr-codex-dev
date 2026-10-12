import Foundation
import Testing
@testable import BetterWisprCore
@testable import BetterWisprShared
@testable import BetterWispr

struct DesktopLibraryTests {
    private func withStores(_ body: (LocalStore, MeetingStore, DesktopLibraryStore) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try body(LocalStore(directory: folder), MeetingStore(directory: folder.appendingPathComponent("Meetings")), DesktopLibraryStore(directory: folder))
    }
    private func transcript(_ text: String) -> Transcript {
        Transcript(text: text, rawText: "raw input", duration: 5, modelName: "Test", language: "en")
    }

    @Test func syncRoundTripPreservesDeviceSettings() throws {
        try withStores { workspace, meetings, adapter in
            var state = SavedState()
            state.settings.selectedModelID = "local-only-model"
            state.settings.autoPaste = false
            state.settings.language = "fr"
            state.settings.showInDock = true
            state.history = [transcript("Desktop")]
            try workspace.save(state)
            let meeting = Meeting(title: "Original", modelName: "Test", language: "en")
            try meetings.save(meeting)
            var remote = LibrarySnapshot()
            remote.history = [transcript("Mobile")]
            remote.vocabulary = [VocabularyEntry(phrase: "post hog", replacement: "PostHog")]
            remote.modes = [WritingMode(name: "Work", tone: .formal)]
            remote.preferences.cleanup = .none
            remote.meetings = [meeting]
            var sync = DesktopSyncState(); sync.baseline = remote
            let destination = DesktopLibraryStore.applying(remote, to: state)
            try adapter.commit(workspace: destination, meetings: remote.meetings, sync: sync)
            let result = try workspace.load()
            #expect(result.settings.selectedModelID == "local-only-model")
            #expect(!result.settings.autoPaste)
            #expect(result.settings.language == "fr")
            #expect(result.settings.showInDock)
            #expect(result.settings.cleanup == .none)
            #expect(DesktopLibraryStore.snapshot(workspace: result, meetings: meetings.load().meetings) == remote)
            #expect(try adapter.loadSync().baseline == remote)
        }
    }

    @Test func interruptedTransactionReplaysAndBlocksOrdinaryWrites() throws {
        try withStores { workspace, meetings, adapter in
            var state = SavedState(); state.history = [transcript("Before")]
            try workspace.save(state)
            let old = Meeting(title: "Delete me", modelName: "Test", language: "en")
            let replacement = Meeting(title: "New meeting", modelName: "Test", language: "en")
            try meetings.save(old)
            state.history[0].text = "After"
            let snapshot = DesktopLibraryStore.snapshot(workspace: state, meetings: [replacement])
            var sync = DesktopSyncState(); sync.baseline = snapshot
            try adapter.stage(workspace: state, meetings: [replacement], sync: sync)
            // Simulate a process exit after only the first destination file was written.
            try meetings.save(replacement, recoveringSync: true)
            #expect(throws: (any Error).self) { try workspace.save(SavedState()) }
            #expect(throws: (any Error).self) { try meetings.delete(id: old.id) }
            try adapter.recover()
            try adapter.recover()
            #expect(try workspace.load().history.first?.text == "After")
            #expect(meetings.load().meetings.map(\.id) == [replacement.id])
            #expect(try adapter.loadSync().baseline == snapshot)
            #expect(!FileManager.default.fileExists(atPath: adapter.pendingURL.path))
        }
    }

    @Test func unreadableMeetingPreventsTransactionWithoutDeletingAnything() throws {
        try withStores { workspace, meetings, adapter in
            try workspace.save(SavedState())
            try FileManager.default.createDirectory(at: meetings.directory, withIntermediateDirectories: true)
            let bad = meetings.directory.appendingPathComponent("broken.json")
            let bytes = Data("not a meeting".utf8); try bytes.write(to: bad)
            #expect(throws: (any Error).self) { try adapter.commit(workspace: SavedState(), meetings: [], sync: DesktopSyncState()) }
            #expect(try Data(contentsOf: bad) == bytes)
            #expect(!FileManager.default.fileExists(atPath: adapter.pendingURL.path))
        }
    }

    @Test func unreadablePendingAndMetadataArePreserved() throws {
        try withStores { workspace, _, adapter in
            try workspace.save(SavedState())
            let bytes = Data("future or damaged".utf8)
            try bytes.write(to: adapter.pendingURL)
            #expect(throws: (any Error).self) { try adapter.recover() }
            #expect(throws: (any Error).self) { try workspace.save(SavedState()) }
            #expect(try Data(contentsOf: adapter.pendingURL) == bytes)
            try FileManager.default.removeItem(at: adapter.pendingURL)
            let metadata = adapter.directory.appendingPathComponent("library-sync.json")
            try bytes.write(to: metadata)
            #expect(throws: (any Error).self) { try adapter.saveSync(DesktopSyncState()) }
            #expect(try Data(contentsOf: metadata) == bytes)
        }
    }

    @MainActor @Test func desktopAppAndMobileJournalExchangeBothWays() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let local = LocalStore(directory: root.appendingPathComponent("Mac"))
        let folder = root.appendingPathComponent("Cloud")
        let app = AppModel(store: local, startsServices: false)
        app.libraryFolder = folder
        app.history = [transcript("From Mac")]
        app.settings.selectedModelID = "apple"
        let meeting = Meeting(title: "Mac meeting", modelName: "Test", language: "en")
        app.meetings.meetings = [meeting]
        await app.synchronizeLibrary()
        #expect(app.librarySyncStatus == "Updated just now")
        let phone = LibraryJournal(directory: folder.appendingPathComponent("BetterWisprLibrary/events"), device: UUID())
        let baseline = try phone.exchange(local: LibrarySnapshot(), baseline: nil)
        #expect(baseline.history.first?.text == "From Mac")
        #expect(baseline.meetings.first?.id == meeting.id)
        var phoneEdits = baseline
        phoneEdits.history.append(transcript("From iPhone"))
        phoneEdits.vocabulary = [VocabularyEntry(phrase: "snow flake", replacement: "Snowflake")]
        phoneEdits.meetings = []
        _ = try phone.exchange(local: phoneEdits, baseline: baseline)
        await app.synchronizeLibrary()
        #expect(app.history.contains { $0.text == "From iPhone" })
        #expect(app.vocabulary.first?.replacement == "Snowflake")
        #expect(app.meetings.meetings.isEmpty)
        #expect(try local.load().history.count == 2)
        let restored = AppModel(store: local, startsServices: false)
        #expect(restored.history.count == 2)
        #expect(restored.meetings.meetings.isEmpty)
        #expect(restored.settings.selectedModelID == "apple")
    }
}
