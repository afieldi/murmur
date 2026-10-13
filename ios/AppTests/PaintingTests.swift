// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import MurmurCore
import Testing
import UIKit
@testable import murmur

/// Takes on fixed days, in UTC, so the tests never depend on the time zone.
@MainActor func paintingTakes(_ days: [(day: Int, count: Int)], words: Int = 60) throws -> [HistoryEntry] {
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = try #require(TimeZone(identifier: "UTC"))
    let start = Date(timeIntervalSince1970: 1_790_000_000)
    return days.flatMap { day, count in
        (0..<count).map { i in
            HistoryEntry(at: start.addingTimeInterval(Double(day) * 86_400 + Double(i) * 600), durationMs: 30_000, words: Array(repeating: "word", count: words).joined(separator: " "), calendar: utc)
        }
    }
}

/// The painting book on iPhone (IOS-019).
@MainActor @Suite(.serialized) struct PaintingStoreTests {
    func scratch() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "paintings-\(UUID().uuidString)", directoryHint: .isDirectory).appending(path: "paintings.json")
    }

    func ladder() throws -> [RankSpec] {
        try BundledRules.journey().ranks.ranks
    }

    /// Takes paint their days, and the book keeps its own seed across launches.
    @Test func takesPaintTheirDaysAndTheBookIsKept() throws {
        let file = scratch()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = PaintingStore(file: file, ladder: try ladder())
        store.sync(try paintingTakes([(0, 3), (1, 2)]))
        #expect(store.book.count == 2)
        #expect(store.book.values.map(\.words.count).sorted() == [2, 3])
        let again = PaintingStore(file: file, ladder: try ladder())
        #expect(again.install == store.install)
        #expect(again.book == store.book)
        let values = try file.deletingLastPathComponent().resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    /// The same takes paint the same book as desktop's code would, with
    /// this install's seed.
    @Test func theBookIsDesktops() throws {
        let store = PaintingStore(file: scratch(), ladder: try ladder())
        let takes = try paintingTakes([(0, 4), (1, 6), (2, 1)])
        store.sync(takes)
        #expect(store.book == Paintings.sync([:], events: takes.map(\.paintingEvent), install: store.install, ladder: try ladder()))
    }

    /// Deleting takes, or clearing them all, keeps what they painted, as
    /// desktop's book outlives its log.
    @Test func deletedTakesKeepTheirPainting() throws {
        let historyFile = FileManager.default.temporaryDirectory.appending(path: "paintings-history-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: historyFile) }
        let store = PaintingStore(file: scratch(), ladder: try ladder())
        let history = History(store: HistoryStore(file: historyFile), keep: { store.sync($0) })
        for take in try paintingTakes([(0, 3)]) { history.add(take) }
        let day = try #require(store.book.keys.first)
        #expect(store.book[day]?.words.count == 3)
        let first = try #require(history.entries.first)
        history.delete(first.id)
        #expect(store.book[day]?.words.count == 3)
        history.clear()
        #expect(store.book[day]?.words.count == 3)
    }

    /// A day that cannot be read is left out; the rest of the book stands.
    @Test func aDayThatCannotBeReadIsLeftOut() throws {
        let file = scratch()
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        try #"""
        {"install": 77, "days": {
          "2026-10-01": {"subject": "moon", "seed": 5, "target": 6, "tier": 0, "level": 1, "words": [12]},
          "2026-10-02": {"subject": "sun", "seed": 5, "target": 6, "tier": 0, "level": 1, "words": [12]},
          "not a day": {"subject": "moon", "seed": 5, "target": 6, "tier": 0, "level": 1, "words": [12]}
        }}
        """#.write(to: file, atomically: true, encoding: .utf8)
        let store = PaintingStore(file: file, ladder: try ladder())
        #expect(store.install == 77)
        #expect(store.book.keys.sorted() == ["2026-10-01"])
    }

    /// A take as the painting sees it: its words, day, and hour, as kept.
    @Test func aTakeAsThePaintingSeesIt() throws {
        let takes = try paintingTakes([(0, 1)], words: 42)
        let take = try #require(takes.first)
        let event = take.paintingEvent
        #expect(event.strokeWords == 42 && event.words == 42 && event.counts)
        #expect(event.day == take.day && event.hour == take.hour)
        #expect(event.at == take.rankEvent.at)
    }
}
