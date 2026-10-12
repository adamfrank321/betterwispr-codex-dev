import SwiftUI
import BetterWisprShared
import UniformTypeIdentifiers

struct DeviceSettings: Codable, Equatable, Sendable {
    var language = "en-US"
    var saveHistory = true
    var learnCorrections = true
    var provider = "apple"
    var endpoint = ""
    var modelID = "whisper-1"
}

struct MobileArchive: Codable, Sendable {
    var version = 1
    var library = LibrarySnapshot()
    var baseline: LibrarySnapshot?
    var settings = DeviceSettings()
}

actor MobileStore {
    private let url: URL
    init() {
        url = URL.applicationSupportDirectory.appendingPathComponent("BetterWisprMobile/library.json")
    }
    func load() throws -> MobileArchive {
        guard FileManager.default.fileExists(atPath: url.path) else { return MobileArchive() }
        let archive = try JSONDecoder().decode(MobileArchive.self, from: Data(contentsOf: url))
        guard archive.version == 1 else { throw LibraryError.unsupportedVersion(archive.version) }
        return archive
    }
    func save(_ archive: MobileArchive) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(archive).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    func exchange(_ library: LibrarySnapshot, baseline: LibrarySnapshot?, folder: URL, device: UUID) throws -> LibrarySnapshot {
        try LibraryJournal(directory: folder.appendingPathComponent("BetterWisprLibrary/events"), device: device)
            .exchange(local: library, baseline: baseline)
    }
}

@MainActor @Observable
final class AppModel {
    enum Phase { case idle, preparing, recording, processing }
    var library = LibrarySnapshot()
    var settings = DeviceSettings()
    var phase = Phase.idle
    var currentText = ""
    var currentRaw = ""
    var message: String?
    var syncStatus = "Sync off"
    var isLoaded = false
    var syncFolder: URL?
    var selectedModeID: UUID?
    var recordingMeeting = false
    let recorder = DictationRecorder()
    @ObservationIgnored private let store = MobileStore()
    @ObservationIgnored private var archive = MobileArchive()
    @ObservationIgnored private var readable = true
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var syncWork: Task<Void, Never>?
    @ObservationIgnored private var session = UUID()
    @ObservationIgnored private var mutation = 0
    @ObservationIgnored private var device: UUID = {
        let defaults = UserDefaults.standard
        if let value = defaults.string(forKey: "deviceID"), let id = UUID(uuidString: value) { return id }
        let id = UUID(); defaults.set(id.uuidString, forKey: "deviceID"); return id
    }()

    var selectedMode: WritingMode? { library.modes.first { $0.id == selectedModeID } }

    func load() async {
        guard !isLoaded else { return }
        do { archive = try await store.load(); library = archive.library; settings = archive.settings }
        catch { readable = false; message = "Saved data could not be read and was preserved. \(error.localizedDescription)" }
        isLoaded = true
        if let data = UserDefaults.standard.data(forKey: "syncBookmark") {
            do {
                var stale = false
                let folder = try URL(resolvingBookmarkData: data, options: .withoutUI, relativeTo: nil, bookmarkDataIsStale: &stale)
                guard !stale, folder.startAccessingSecurityScopedResource() else { throw CocoaError(.fileReadNoPermission) }
                syncFolder = folder
            } catch { syncStatus = "Reconnect folder"; message = "Choose the sync folder again to restore access." }
        }
        do { try publishKeyboard() } catch { message = error.localizedDescription }
        await synchronize()
    }

    func persist() async {
        guard readable else { message = "The unreadable library was preserved. Restore a backup before editing."; return }
        mutation += 1
        archive.library = library; archive.settings = settings
        let saved = archive
        do { try await store.save(saved); try publishKeyboard() }
        catch { message = "Could not save: \(error.localizedDescription)" }
    }

    func connect(_ folder: URL) async {
        guard phase == .idle else { message = "Finish recording before connecting a folder."; return }
        guard folder.startAccessingSecurityScopedResource() else { message = "Could not access the folder."; return }
        do {
            let bookmark = try folder.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
            // Do not replace the previous connection until the new folder is usable.
            _ = try await store.exchange(library, baseline: nil, folder: folder, device: device)
            syncFolder?.stopAccessingSecurityScopedResource()
            syncFolder = folder; archive.baseline = nil
            UserDefaults.standard.set(bookmark, forKey: "syncBookmark")
            await synchronize()
        } catch { folder.stopAccessingSecurityScopedResource(); message = error.localizedDescription }
    }

    func disconnect() async {
        // Complete an in-flight coordinated exchange before closing its security scope.
        if let syncWork { await syncWork.value }
        syncFolder?.stopAccessingSecurityScopedResource(); syncFolder = nil
        archive.baseline = nil; syncStatus = "Sync off"
        UserDefaults.standard.removeObject(forKey: "syncBookmark")
        await persist()
    }

    func synchronize() async {
        guard readable, let folder = syncFolder, phase == .idle, syncWork == nil else { return }
        let local = library, baseline = archive.baseline, revision = mutation
        syncStatus = "Syncing…"
        let task = Task { @MainActor in
            do {
                let merged = try await store.exchange(local, baseline: baseline, folder: folder, device: device)
                // UI edits made during I/O are carried forward against the returned baseline.
                var values = merged.values
                if revision != mutation {
                    let before = local.values, after = library.values
                    for key in Set(before.keys).union(after.keys) where before[key] != after[key] { values[key] = after[key] }
                }
                library = LibrarySnapshot(values: values)
                archive.baseline = merged
                await persist()
                syncStatus = revision == mutation - 1 ? "Updated just now" : "Changes pending"
            } catch { syncStatus = "Sync needs attention"; message = error.localizedDescription }
        }
        syncWork = task
        await task.value
        syncWork = nil
    }

    func start(meeting: Bool = false) {
        guard readable, isLoaded, phase == .idle else { return }
        recordingMeeting = meeting
        currentText = ""; currentRaw = ""; phase = .preparing
        let token = UUID(); session = token
        work = Task { @MainActor in
            do {
                try await recorder.start()
                try Task.checkCancellation()
                guard session == token else { return }
                phase = .recording
                recorder.onLimit = { [weak self] in self?.finish() }
            } catch {
                guard session == token else { return }
                phase = .idle; message = error.localizedDescription; recorder.cancel()
            }
        }
    }

    func finish() {
        guard phase == .recording else { return }
        let token = session, meeting = recordingMeeting
        let capturedLibrary = library, capturedSettings = settings, mode = selectedMode
        phase = .processing
        work = Task { @MainActor in
            do {
                let audio = try recorder.stop()
                defer { try? FileManager.default.removeItem(at: audio.url) }
                let raw: String
                if capturedSettings.provider == "api" {
                    raw = try await CloudTranscriber.transcribe(audio.url, settings: capturedSettings)
                } else {
                    raw = try await recorder.transcribe(audio.url, language: capturedSettings.language,
                                                       hints: VocabularyProcessor.hints(capturedLibrary.vocabulary))
                }
                try Task.checkCancellation()
                guard token == session else { return }
                let output = DictationPipeline.process(raw, language: capturedSettings.language, library: capturedLibrary, selectedMode: mode)
                currentRaw = raw; currentText = output.text
                guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw DictationError.noSpeech }
                let name = capturedSettings.provider == "api" ? capturedSettings.modelID : "Apple on-device"
                if meeting {
                    var item = Meeting(title: "Meeting \(Date.now.formatted(date: .abbreviated, time: .shortened))", duration: audio.duration,
                                       modelName: name, language: capturedSettings.language)
                    item.segments = [MeetingSegment(speaker: .me, start: 0, duration: audio.duration, text: output.text, rawText: raw)]
                    library.meetings.insert(item, at: 0)
                } else if capturedSettings.saveHistory {
                    library.history.insert(Transcript(text: output.text, rawText: raw, duration: audio.duration, modelName: name,
                                                      language: capturedSettings.language, vocabularyFixes: output.vocabularyFixes), at: 0)
                }
                if (mode?.cleanup ?? capturedLibrary.preferences.cleanup) == .medium {
                    message = "Saved with Light cleanup. Medium needs a notes model, which this first version does not include."
                }
                phase = .idle
                await persist(); await synchronize()
            } catch {
                guard token == session else { return }
                phase = .idle; message = error.localizedDescription; recorder.cancel()
            }
        }
    }

    func cancel() {
        session = UUID(); work?.cancel(); work = nil
        recorder.cancel(); phase = .idle
    }

    func edit(_ transcript: Transcript, text: String, learn: Bool = true) async {
        guard let index = library.history.firstIndex(where: { $0.id == transcript.id }) else { return }
        if learn && settings.learnCorrections {
            for correction in CorrectionLearner.corrections(from: transcript.text, to: text) {
                guard !library.vocabulary.contains(where: { $0.phrase.caseInsensitiveCompare(correction.heard) == .orderedSame }) else { continue }
                library.vocabulary.append(VocabularyEntry(phrase: correction.heard, replacement: correction.corrected, learned: true))
            }
        }
        library.history[index].text = text
        await persist(); await synchronize()
    }

    func publishKeyboard() throws {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "BetterWisprAppGroup") as? String,
              let folder = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
            throw CocoaError(.fileWriteNoPermission)
        }
        let items = Array(library.history.prefix(25))
        try JSONEncoder().encode(items).write(to: folder.appendingPathComponent("keyboard.json"),
                                             options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
