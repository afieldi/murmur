// SPDX-License-Identifier: GPL-3.0-only
// History (ios/prd.json IOS-012): every take that came back as words,
// kept only in the app's own container, never in the app group the
// keyboard shares and never in iCloud backups, so it never leaves the
// phone. One line per take, newest last on disk and first on screen.
import Foundation
import Observation

struct HistoryEntry: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    /// When the take was spoken.
    let at: Date
    /// How long it recorded.
    let durationMs: Int
    let words: String
    let wordCount: Int
    /// A take that failed first and came back on a retry (IOS-006).
    let retried: Bool

    init(id: UUID = UUID(), at: Date, durationMs: Int, words: String, retried: Bool = false) {
        self.id = id
        self.at = at
        self.durationMs = max(0, durationMs)
        self.words = words
        wordCount = words.split(whereSeparator: \.isWhitespace).count
        self.retried = retried
    }
}

struct HistoryStore: Sendable {
    let file: URL

    static let standard = HistoryStore(file: URL.applicationSupportDirectory.appending(path: "history", directoryHint: .isDirectory).appending(path: "history.jsonl"))

    /// Adds a take at the end, creating the file (out of backups, writable
    /// after first unlock, as a take may land with the phone locked).
    func append(_ entry: HistoryEntry) throws {
        try prepare()
        var line = try JSONEncoder().encode(entry)
        line.append(0x0A)
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
    }

    /// Every take, newest first; a line that cannot be read is skipped.
    func list() -> [HistoryEntry] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        let decoder = JSONDecoder()
        return data.split(separator: 0x0A).compactMap { try? decoder.decode(HistoryEntry.self, from: Data($0)) }.reversed()
    }

    func remove(_ id: UUID) throws {
        let kept = list().reversed().filter { $0.id != id }
        try rewrite(Array(kept))
    }

    func clear() throws {
        if FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.removeItem(at: file)
        }
    }

    private func rewrite(_ entries: [HistoryEntry]) throws {
        try prepare()
        let encoder = JSONEncoder()
        var data = Data()
        for entry in entries {
            data.append(try encoder.encode(entry))
            data.append(0x0A)
        }
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private func prepare() throws {
        let folder = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = folder
        try url.setResourceValues(values)
        if !FileManager.default.fileExists(atPath: file.path) {
            try Data().write(to: file, options: .completeFileProtectionUntilFirstUserAuthentication)
        }
    }
}

/// The history the app shows: the store, read once and kept current.
@Observable @MainActor final class History {
    private(set) var entries: [HistoryEntry]
    @ObservationIgnored private let store: HistoryStore

    init(store: HistoryStore) {
        self.store = store
        entries = store.list()
    }

    /// A take that came back as words. If the disk refuses it, it still
    /// shows until murmur closes.
    func add(_ entry: HistoryEntry) {
        try? store.append(entry)
        entries.insert(entry, at: 0)
    }

    func delete(_ id: UUID) {
        try? store.remove(id)
        entries = store.list()
    }

    func clear() {
        try? store.clear()
        entries = []
    }
}

extension History {
    private static var shared: History?

    /// The app's one history.
    static func live() -> History {
        if let shared { return shared }
        let history = History(store: .standard)
        shared = history
        return history
    }
}
