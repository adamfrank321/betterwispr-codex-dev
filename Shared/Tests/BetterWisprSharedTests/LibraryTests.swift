import Foundation
import Testing
@testable import BetterWisprShared

struct LibraryTests {
    private func transcript(_ text: String = "Original") -> Transcript {
        Transcript(text: text, rawText: "original audio text", duration: 5, modelName: "Test", language: "en-US")
    }
    private func withJournal(_ body: (LibraryJournal) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try body(LibraryJournal(directory: folder, device: UUID()))
    }

    @Test func offlineUpdatesConvergeWithoutOverwritingUnrelatedRecords() throws {
        try withJournal { a in
            let b = LibraryJournal(directory: a.directory, device: UUID())
            var initial = LibrarySnapshot(); initial.history = [transcript()]
            let baseline = try a.exchange(local: initial, baseline: nil)
            let bBaseline = try b.exchange(local: LibrarySnapshot(), baseline: nil)
            var aLocal = baseline; aLocal.history[0].text = "Edited on A"
            var bLocal = bBaseline; bLocal.vocabulary = [VocabularyEntry(phrase: "snow flake", replacement: "Snowflake")]
            _ = try a.exchange(local: aLocal, baseline: baseline)
            let merged = try b.exchange(local: bLocal, baseline: bBaseline)
            #expect(merged.history.first?.text == "Edited on A")
            #expect(merged.vocabulary.first?.replacement == "Snowflake")
            #expect(merged.history.first?.rawText == "original audio text")
        }
    }

    @Test func deletionSurvivesReconnectAndRepeatedExchangeIsIdempotent() throws {
        try withJournal { journal in
            var local = LibrarySnapshot(); local.history = [transcript()]
            let initial = try journal.exchange(local: local, baseline: nil)
            var deleted = initial; deleted.history = []
            let afterDelete = try journal.exchange(local: deleted, baseline: initial)
            let count = try journal.events().count
            _ = try journal.exchange(local: afterDelete, baseline: afterDelete)
            #expect(try journal.events().count == count)
            let returningDevice = LibraryJournal(directory: journal.directory, device: UUID())
            #expect(try returningDevice.exchange(local: local, baseline: nil).history.isEmpty)
        }
    }

    @Test func concurrentConflictsHaveOrderIndependentWinner() throws {
        let item = transcript(); var edited = item; edited.text = "Second version"
        let first = LibraryEvent(device: UUID(), counter: 7, key: LibraryValue.transcript(item).key, value: .transcript(item))
        let second = LibraryEvent(device: UUID(), counter: 7, key: first.key, value: .transcript(edited))
        #expect(try LibraryJournal.snapshot([first, second]) == LibraryJournal.snapshot([second, first]))
    }

    @Test func corruptFilesPauseExchangeAndRemainUntouched() throws {
        try withJournal { journal in
            var local = LibrarySnapshot(); local.history = [transcript()]
            _ = try journal.exchange(local: local, baseline: nil)
            let file = journal.directory.appendingPathComponent("corrupt.json")
            let bytes = Data("not json".utf8); try bytes.write(to: file)
            #expect(throws: (any Error).self) { try journal.exchange(local: local, baseline: local) }
            #expect(try Data(contentsOf: file) == bytes)
        }
    }

    @Test func mismatchedPayloadIsRejected() {
        let item = transcript()
        let invalid = LibraryEvent(device: UUID(), counter: 1, key: "preferences", value: .transcript(item))
        #expect(throws: (any Error).self) { try invalid.validate() }
    }

    @Test func emptyLibraryDoesNotContainCredentialsOrAudio() throws {
        let encoded = String(decoding: try JSONEncoder().encode(LibrarySnapshot()), as: UTF8.self)
        #expect(!encoded.contains("apiKey"))
        #expect(!encoded.contains("endpoint"))
    }

    @Test func pipelineUsesVocabularyAndKeepsInputValue() {
        var library = LibrarySnapshot()
        library.vocabulary = [VocabularyEntry(phrase: "snow flake", replacement: "Snowflake")]
        let raw = "I use snow flake."
        let output = DictationPipeline.process(raw, language: "en-US", library: library)
        #expect(output.text.contains("Snowflake"))
        #expect(raw == "I use snow flake.")
    }
    @Test func editsDuringSyncPreserveLocalChangesAndRemoteAdditions() {
        var before = LibrarySnapshot(); before.history = [transcript()]
        var local = before; local.history = []
        local.vocabulary = [VocabularyEntry(phrase: "my word", replacement: "MyWord")]
        var remote = before; let added = transcript("Remote addition"); remote.history.append(added)
        let merged = LibrarySnapshot.rebasingChanges(from: before, to: local, onto: remote)
        #expect(merged.history.map(\.id) == [added.id])
        #expect(merged.vocabulary == local.vocabulary)
    }
}
