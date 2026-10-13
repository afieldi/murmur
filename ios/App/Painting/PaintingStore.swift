// SPDX-License-Identifier: GPL-3.0-only
// The painting book on iPhone (ios/prd.json IOS-019): a record per day,
// kept in the app's own container and out of backups, so the paintings
// outlive deleted takes, as desktop's paintings.json does. Word counts
// only, never text. It is brought up to date when a take lands, and before
// takes are deleted.
import Foundation
import MurmurCore
import Observation

/// The book on disk: this install's own seed and the paintings by day.
struct PaintingFile: Codable {
    var install: UInt32
    var days: PaintingBook

    private enum Keys: String, CodingKey { case install, days }

    init(install: UInt32, days: PaintingBook) {
        self.install = install
        self.days = days
    }

    /// A day that cannot be read is left out; the rest stand, as desktop
    /// reads its book.
    init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: Keys.self)
        install = try box.decode(UInt32.self, forKey: .install)
        let days = (try? box.decode([String: Lenient].self, forKey: .days)) ?? [:]
        self.days = days.compactMapValues(\.record).filter { Paintings.isDayKey($0.key) }
    }

    func encode(to encoder: any Encoder) throws {
        var box = encoder.container(keyedBy: Keys.self)
        try box.encode(install, forKey: .install)
        try box.encode(days, forKey: .days)
    }

    private struct Lenient: Decodable {
        let record: PaintingRecord?

        init(from decoder: any Decoder) throws {
            record = try? PaintingRecord(from: decoder)
        }
    }
}

@Observable @MainActor final class PaintingStore {
    private(set) var book: PaintingBook
    @ObservationIgnored let install: UInt32
    @ObservationIgnored private let file: URL
    @ObservationIgnored private let ladder: [RankSpec]

    static let standardFile = URL.applicationSupportDirectory.appending(path: "paintings", directoryHint: .isDirectory).appending(path: "paintings.json")

    init(file: URL, ladder: [RankSpec]) {
        self.file = file
        self.ladder = ladder
        let kept = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(PaintingFile.self, from: $0) }
        install = kept?.install ?? UInt32.random(in: .min ... .max)
        book = kept?.days ?? [:]
    }

    /// Brings the book up to date with these takes, and keeps it.
    func sync(_ entries: [HistoryEntry]) {
        let next = Paintings.sync(book, events: entries.map(\.paintingEvent), install: install, ladder: ladder)
        guard next != book || !FileManager.default.fileExists(atPath: file.path) else { return }
        book = next
        try? save()
    }

    private func save() throws {
        let folder = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = folder
        try url.setResourceValues(values)
        let data = try JSONEncoder().encode(PaintingFile(install: install, days: book))
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

extension PaintingStore {
    private static var shared: PaintingStore?

    /// The app's one book; nil only if the app's own ladder could not be read.
    static func live() -> PaintingStore? {
        if let shared { return shared }
        guard let ladder = JourneyRules.live?.ranks.ranks else { return nil }
        let store = PaintingStore(file: standardFile, ladder: ladder)
        shared = store
        return store
    }
}
