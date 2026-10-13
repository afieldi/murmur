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

/// Whether this build carries the cards' display face: it is fetched at
/// install, so a build made offline goes without it (IOS-019).
func pageHasDisplayFace() -> Bool {
    guard let url = JourneyPage.url, let page = try? String(contentsOf: url, encoding: .utf8) else { return false }
    return page.contains(#"font-family: "murmur display""#)
}

/// A painting a day from the painter page (IOS-019).
@MainActor @Suite(.serialized) struct PaintingPictureTests {
    func book() throws -> PaintingBook {
        let ladder = try BundledRules.journey().ranks.ranks
        return Paintings.sync([:], events: try paintingTakes([(0, 7), (1, 3), (3, 6)]).map(\.paintingEvent), install: 4242, ladder: ladder)
    }

    /// A day's painting at rest is painted at its size, and is not blank.
    @Test func aDayIsPainted() async throws {
        let book = try book()
        let record = try #require(book.values.first)
        let picture = try await JourneyPainter.started().picture(.painting(record, width: 120, height: 90), scale: 2)
        #expect(picture.image.size == CGSize(width: 120, height: 90))
        let alpha = PaintingDifference.bytes(picture.image).enumerated().filter { $0.offset % 4 == 3 && $0.element > 20 }.count
        #expect(alpha > 100)
    }

    /// The card is desktop's 1080 by 1350 and the week's scroll its 3968
    /// by 864, with the titles in the display face when the build has it.
    @Test func theCardAndTheWeekAreDesktops() async throws {
        let book = try book()
        let last = try #require(book.keys.sorted().last)
        let record = try #require(book[last])
        let painter = try await JourneyPainter.started()
        let cardData = try await painter.png(.card(day: last, record: record, longestMs: 90_000), scale: 2).data
        let card = try #require(UIImage(data: cardData))
        #expect(card.size == CGSize(width: 1080, height: 1350))
        let weekData = try await painter.png(.week(last: last, book: book), scale: 2).data
        let week = try #require(UIImage(data: weekData))
        #expect(week.size == CGSize(width: 3968, height: 864))
        let face = try await painter.web.callAsyncJavaScript(
            "return Array.from(document.fonts).some((f) => f.family.replace(/[\"']/g, '') === 'murmur display' && f.status === 'loaded')", arguments: [:], contentWorld: .page
        )
        #expect(face as? Bool == pageHasDisplayFace())
    }

    /// Today's painting on the page's canvases: at rest, or with its newest
    /// stroke painting in, it ends painted.
    @Test func todayPaintsLive() async throws {
        let book = try book()
        let record = try #require(book.values.first)
        let painter = try await JourneyPainter.started()
        try await painter.onScreen(CGSize(width: 360, height: 270))
        defer { painter.web.removeFromSuperview() }
        func ink() async throws -> Int {
            let sum = try await painter.web.evaluateJavaScript(
                "(() => { const c = document.getElementById('base'); const d = c.getContext('2d').getImageData(0, 0, c.width, c.height).data; let n = 0; for (let i = 3; i < d.length; i += 4) n += d[i] > 20 ? 1 : 0; return n })()"
            )
            return (sum as? Int) ?? -1
        }
        try await painter.live(record, size: CGSize(width: 360, height: 270), fresh: false, doneBefore: 0, reduced: false)
        let rest = try await ink()
        #expect(rest > 100)
        try await painter.live(record, size: CGSize(width: 360, height: 270), fresh: true, doneBefore: 0, reduced: false)
        try await Task.sleep(for: .seconds(1.3))
        #expect(abs(try await ink() - rest) <= rest / 50)
    }
}
