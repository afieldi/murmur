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

/// What the painting screens remember and say (IOS-019).
@Suite struct PaintingWordsTests {
    func seen() -> (PaintingSeen, UserDefaults, String) {
        let name = "painting-seen-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        return (PaintingSeen(defaults: defaults), defaults, name)
    }

    /// The newest stroke paints in only when it is new since the last look;
    /// the strokes done when last seen today say whether it just finished.
    @Test func theNewestStrokePaintsInOnce() {
        let (seen, defaults, name) = seen()
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(seen.look(day: "2026-10-13", done: 3) == (true, 0))
        seen.remember(day: "2026-10-13", done: 3)
        #expect(seen.look(day: "2026-10-13", done: 3) == (false, 3))
        #expect(seen.look(day: "2026-10-13", done: 4) == (true, 3))
        #expect(seen.look(day: "2026-10-14", done: 1) == (true, 0))
    }

    @Test func theLinesAreDesktops() {
        var record = PaintingRecord(subject: .lotus, seed: 1, target: 6, tier: 0, level: 1, rank: "white", hour: 20, words: [10, 20, 30])
        #expect(PaintingCopy.line(record, longestMs: nil) == "Every take adds the next stroke. 3 more to finish it.")
        record.words = Array(repeating: 10, count: 8)
        #expect(PaintingCopy.line(record, longestMs: 125_000) == "8 takes, 80 words. The longest ran 2:05. Every take from here adds to it.")
        record.words = Array(repeating: 1, count: 6 + Paintings.maxExtra)
        #expect(!PaintingCopy.line(record, longestMs: nil).hasSuffix("adds to it."))
        #expect(PaintingCopy.stripCaption(record) == "lotus pond")
        record.words = [1, 1]
        #expect(PaintingCopy.stripCaption(record) == "2 of 6")
    }

    /// The strip names the last week's days by weekday, older ones by date.
    @Test func theStripNamesItsDays() {
        #expect(PaintingCopy.stripDay("2026-10-12", today: "2026-10-13") == "Mon")
        #expect(PaintingCopy.stripDay("2026-10-07", today: "2026-10-13") == "Wed")
        #expect(PaintingCopy.stripDay("2026-10-06", today: "2026-10-13") == "Oct 6")
        #expect(PaintingCopy.cardName("2026-10-13") == "murmur-day-2026-10-13.png")
        #expect(PaintingCopy.weekName("2026-10-13") == "murmur-week-2026-10-13.png")
    }

    @Test func everyLineFollowsTheWritingRules() {
        for line in [PaintingCopy.title, PaintingCopy.past, PaintingCopy.saveCard, PaintingCopy.saveWeek, PaintingCopy.firstTake, PaintingCopy.kept, PaintingCopy.fromHere, PaintingCopy.toFinish(2)] {
            #expect(!line.contains("Murmur"))
            #expect(!line.contains("\u{2014}") && !line.contains(" - ") && !line.contains("--"))
        }
    }
}

/// The share sheet's pictures (IOS-019).
@MainActor @Suite(.serialized) struct PaintingShareTests {
    func book() throws -> PaintingBook {
        let ladder = try BundledRules.journey().ranks.ranks
        return Paintings.sync([:], events: try paintingTakes([(0, 7), (1, 3), (3, 6)]).map(\.paintingEvent), install: 4242, ladder: ladder)
    }

    /// The share sheet's picture is the card, painted when it is asked for.
    @Test func theShareIsTheCard() async throws {
        let book = try book()
        let last = try #require(book.keys.sorted().last)
        let record = try #require(book[last])
        let share = PaintingShare(name: PaintingCopy.cardName(last), artwork: .card(day: last, record: record, longestMs: nil))
        let data = try await share.png()
        #expect(UIImage(data: data)?.size == CGSize(width: 1080, height: 1350))
    }
}
