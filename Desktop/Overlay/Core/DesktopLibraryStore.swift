import Foundation
import BetterWisprShared

public struct DesktopSyncState: Codable, Sendable {
    public var version = 1
    public var device = UUID()
    public var bookmark: Data?
    public var securityScoped: Bool?
    public var baseline: LibrarySnapshot?
    public init() {}
}

public enum DesktopSyncError: LocalizedError {
    case pendingRecovery, unreadableMeetings, invalidVersion
    public var errorDescription: String? {
        switch self {
        case .pendingRecovery: "A library save needs recovery. Restart BetterWispr before making more changes. Existing files were preserved."
        case .unreadableMeetings: "A meeting file could not be read. Library sync paused and the file was preserved."
        case .invalidVersion: "The saved library sync format requires a newer app. Files were preserved."
        }
    }
}

/// Owns the local, replayable commit across workspace, meetings and sync baseline.
/// Called only by the app's main-actor persistence owner, never by a file watcher.
public struct DesktopLibraryStore: Sendable {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }
    public var pendingURL: URL { directory.appendingPathComponent("library-sync-pending.json") }
    private var metadataURL: URL { directory.appendingPathComponent("library-sync.json") }
    private var workspace: LocalStore { LocalStore(directory: directory) }
    private var meetings: MeetingStore { MeetingStore(directory: directory.appendingPathComponent("Meetings")) }

    struct Pending: Codable {
        var version = 1
        var workspace: SavedState
        var meetings: [Meeting]
        var sync: DesktopSyncState
    }

    public static func requireNoPending(in directory: URL) throws {
        if FileManager.default.fileExists(atPath: directory.appendingPathComponent("library-sync-pending.json").path) {
            throw DesktopSyncError.pendingRecovery
        }
    }

    public func loadSync() throws -> DesktopSyncState {
        guard FileManager.default.fileExists(atPath: metadataURL.path) else { return DesktopSyncState() }
        let result = try JSONDecoder().decode(DesktopSyncState.self, from: Data(contentsOf: metadataURL))
        guard result.version == 1 else { throw DesktopSyncError.invalidVersion }
        return result
    }

    public func saveSync(_ state: DesktopSyncState) throws {
        try Self.requireNoPending(in: directory)
        _ = try loadSync() // Preserve malformed or future metadata.
        try write(state, to: metadataURL)
    }

    public static func snapshot(workspace: SavedState, meetings: [Meeting]) -> LibrarySnapshot {
        var result = LibrarySnapshot()
        result.history = workspace.history
        result.vocabulary = workspace.vocabulary
        result.modes = workspace.settings.modes
        result.meetings = meetings
        result.preferences = WritingPreferences(cleanup: workspace.settings.cleanup, styles: workspace.settings.styles)
        return result
    }

    public static func applying(_ snapshot: LibrarySnapshot, to current: SavedState) -> SavedState {
        var result = current
        result.history = snapshot.history
        result.vocabulary = snapshot.vocabulary
        result.settings.modes = snapshot.modes
        result.settings.cleanup = snapshot.preferences.cleanup
        result.settings.styles = snapshot.preferences.styles
        return result
    }

    /// Persist intent before changing any of the destination files.
    func stage(workspace: SavedState, meetings: [Meeting], sync: DesktopSyncState) throws {
        try Self.requireNoPending(in: directory)
        try validateExisting()
        _ = try loadSync()
        try write(Pending(workspace: workspace, meetings: meetings, sync: sync), to: pendingURL)
    }

    public func commit(workspace: SavedState, meetings: [Meeting], sync: DesktopSyncState) throws {
        try stage(workspace: workspace, meetings: meetings, sync: sync)
        try recover()
    }

    /// Startup calls this before constructing either of the desktop models.
    public func recover() throws {
        guard FileManager.default.fileExists(atPath: pendingURL.path) else { return }
        let pending = try JSONDecoder().decode(Pending.self, from: Data(contentsOf: pendingURL))
        guard pending.version == 1, pending.workspace.version == 1, pending.sync.version == 1 else {
            throw DesktopSyncError.invalidVersion
        }
        try validateExisting()
        _ = try loadSync()
        let old = meetings.load().meetings
        for meeting in pending.meetings { try meetings.save(meeting, recoveringSync: true) }
        let retained = Set(pending.meetings.map(\.id))
        for meeting in old where !retained.contains(meeting.id) { try meetings.delete(id: meeting.id, recoveringSync: true) }
        try workspace.save(pending.workspace, recoveringSync: true)
        try write(pending.sync, to: metadataURL)
        try FileManager.default.removeItem(at: pendingURL)
    }

    private func validateExisting() throws {
        _ = try workspace.load()
        if FileManager.default.fileExists(atPath: meetings.directory.path) {
            // MeetingStore.load treats listing failure as an empty library; sync must not.
            _ = try FileManager.default.contentsOfDirectory(at: meetings.directory, includingPropertiesForKeys: nil)
        }
        guard meetings.load().unreadable.isEmpty else { throw DesktopSyncError.unreadableMeetings }
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let data = try JSONEncoder().encode(value)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

public actor DesktopLibraryExchange {
    public init() {}
    public func exchange(_ local: LibrarySnapshot, baseline: LibrarySnapshot?, folder: URL, device: UUID) throws -> LibrarySnapshot {
        try LibraryJournal(directory: folder.appendingPathComponent("BetterWisprLibrary/events"), device: device)
            .exchange(local: local, baseline: baseline)
    }
}
