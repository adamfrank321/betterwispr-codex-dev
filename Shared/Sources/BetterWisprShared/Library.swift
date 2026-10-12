import Foundation

public struct WritingPreferences: Codable, Equatable, Sendable {
    public var cleanup: CleanupLevel
    public var styles: [StyleContext: StyleTone]
    public init(cleanup: CleanupLevel = .light, styles: [StyleContext: StyleTone] = [:]) {
        self.cleanup = cleanup
        self.styles = styles
    }
}

public struct LibrarySnapshot: Codable, Equatable, Sendable {
    public var history: [Transcript] = []
    public var vocabulary: [VocabularyEntry] = []
    public var modes: [WritingMode] = []
    public var meetings: [Meeting] = []
    public var preferences = WritingPreferences()
    public init() {}

    public var values: [String: LibraryValue] {
        var result = [String: LibraryValue]()
        for item in history { result["transcript/\(item.id.uuidString)"] = .transcript(item) }
        for item in vocabulary { result["vocabulary/\(item.id.uuidString)"] = .vocabulary(item) }
        for item in modes { result["mode/\(item.id.uuidString)"] = .mode(item) }
        for item in meetings { result["meeting/\(item.id.uuidString)"] = .meeting(item) }
        result["preferences"] = .preferences(preferences)
        return result
    }

    public init(values: [String: LibraryValue]) {
        self.init()
        for value in values.values {
            switch value {
            case .transcript(let item): history.append(item)
            case .vocabulary(let item): vocabulary.append(item)
            case .mode(let item): modes.append(item)
            case .meeting(let item): meetings.append(item)
            case .preferences(let item): preferences = item
            }
        }
        history.sort { $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt > $1.createdAt }
        meetings.sort { $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt > $1.createdAt }
        vocabulary.sort { $0.id.uuidString < $1.id.uuidString }
        modes.sort { $0.id.uuidString < $1.id.uuidString }
    }
}

public enum LibraryValue: Codable, Equatable, Sendable {
    case transcript(Transcript), vocabulary(VocabularyEntry), mode(WritingMode), meeting(Meeting), preferences(WritingPreferences)
    public var key: String {
        switch self {
        case .transcript(let item): "transcript/\(item.id.uuidString)"
        case .vocabulary(let item): "vocabulary/\(item.id.uuidString)"
        case .mode(let item): "mode/\(item.id.uuidString)"
        case .meeting(let item): "meeting/\(item.id.uuidString)"
        case .preferences: "preferences"
        }
    }
}

public struct LibraryEvent: Codable, Equatable, Sendable {
    public let version: Int
    public let id: UUID
    public let device: UUID
    public let counter: UInt64
    public let key: String
    public let value: LibraryValue?
    public init(id: UUID = UUID(), device: UUID, counter: UInt64, key: String, value: LibraryValue?) {
        version = 1
        self.id = id
        self.device = device
        self.counter = counter
        self.key = key
        self.value = value
    }
    public func isLater(than other: LibraryEvent) -> Bool {
        if counter != other.counter { return counter > other.counter }
        if device != other.device { return device.uuidString > other.device.uuidString }
        return id.uuidString > other.id.uuidString
    }
    public func validate() throws {
        guard version == 1 else { throw LibraryError.unsupportedVersion(version) }
        let components = key.split(separator: "/")
        let valid = key == "preferences" || (components.count == 2
            && ["transcript", "vocabulary", "mode", "meeting"].contains(String(components[0]))
            && UUID(uuidString: String(components[1])) != nil)
        guard valid, value == nil || value?.key == key else { throw LibraryError.invalidEvent(key) }
    }
}

public enum LibraryError: LocalizedError {
    case unsupportedVersion(Int), invalidEvent(String), unreadableFile(String), clockExhausted
    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version): "Library version \(version) needs a newer app. Files were preserved."
        case .invalidEvent(let key): "Invalid library record \(key). Files were preserved."
        case .unreadableFile(let file): "Could not read \(file). Sync paused to preserve the library. Download the folder in Files and retry."
        case .clockExhausted: "The library revision counter is exhausted."
        }
    }
}

/// Immutable files are never rewritten by a second device. No wall-clock ordering.
public struct LibraryJournal: Sendable {
    public let directory: URL
    public let device: UUID
    public init(directory: URL, device: UUID) { self.directory = directory; self.device = device }

    public func events() throws -> [LibraryEvent] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let keys: Set<URLResourceKey> = [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys))
        if let placeholder = urls.first(where: { $0.pathExtension == "icloud" }) {
            throw LibraryError.unreadableFile(placeholder.lastPathComponent)
        }
        return try urls.filter { $0.pathExtension == "json" }.map { url in
            let status = try url.resourceValues(forKeys: keys)
            if status.isUbiquitousItem == true, status.ubiquitousItemDownloadingStatus != .current {
                throw LibraryError.unreadableFile(url.lastPathComponent)
            }
            let event: LibraryEvent
            do { event = try JSONDecoder().decode(LibraryEvent.self, from: coordinatedRead(url)) }
            catch { throw LibraryError.unreadableFile(url.lastPathComponent) }
            try event.validate()
            return event
        }
    }

    public static func snapshot(_ events: [LibraryEvent]) throws -> LibrarySnapshot {
        var newest = [String: LibraryEvent]()
        for event in events {
            try event.validate()
            if let previous = newest[event.key], !event.isLater(than: previous) { continue }
            newest[event.key] = event
        }
        return LibrarySnapshot(values: newest.compactMapValues(\.value))
    }

    /// Publish only changes relative to this device's last accepted snapshot.
    /// On first connection, import missing local records but respect existing remote tombstones.
    public func exchange(local: LibrarySnapshot, baseline: LibrarySnapshot?) throws -> LibrarySnapshot {
        var existing = try events()
        var counter = existing.map(\.counter).max() ?? 0
        let before = baseline?.values ?? [:], after = local.values
        let remoteKeys = Set(existing.map(\.key))
        // Missing files are not deletion events. A partially delivered directory must not erase local records.
        if baseline != nil, !Set(before.keys).isSubset(of: remoteKeys) {
            throw LibraryError.unreadableFile("previously synchronized library records")
        }
        let keys = Set(before.keys).union(after.keys).sorted()
        for key in keys {
            if baseline == nil, remoteKeys.contains(key) { continue }
            guard before[key] != after[key] else { continue }
            guard counter < UInt64.max else { throw LibraryError.clockExhausted }
            counter += 1
            let event = LibraryEvent(device: device, counter: counter, key: key, value: after[key])
            try append(event)
            existing.append(event)
        }
        return try Self.snapshot(existing)
    }

    public func append(_ event: LibraryEvent) throws {
        try event.validate()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(event.device.uuidString)-\(event.id.uuidString).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(event)
        var coordinationError: NSError?
        var writeError: (any Error)?
        NSFileCoordinator().coordinate(writingItemAt: url, options: [], error: &coordinationError) { target in
            do {
                if FileManager.default.fileExists(atPath: target.path) {
                    guard try Data(contentsOf: target) == bytes else { throw LibraryError.invalidEvent(event.key) }
                } else { try bytes.write(to: target, options: .atomic) }
            } catch { writeError = error }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
    }

    private func coordinatedRead(_ url: URL) throws -> Data {
        var coordinationError: NSError?
        var result: Result<Data, any Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { target in
            result = Result { try Data(contentsOf: target) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw LibraryError.unreadableFile(url.lastPathComponent) }
        return try result.get()
    }
}

extension LibrarySnapshot {
    /// Preserve edits made while remote I/O was in flight, including local deletions.
    public static func rebasingChanges(from before: LibrarySnapshot, to current: LibrarySnapshot,
                                       onto remote: LibrarySnapshot) -> LibrarySnapshot {
        var result = remote.values
        let old = before.values, new = current.values
        for key in Set(old.keys).union(new.keys) where old[key] != new[key] { result[key] = new[key] }
        return LibrarySnapshot(values: result)
    }
}
