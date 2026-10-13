// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import MurmurCore
import Testing
@testable import murmur

/// Belts and stripes on iPhone (IOS-017).
@Suite struct JourneyTests {
    let at = Date(timeIntervalSince1970: 1_790_000_000)

    func calendar(_ zone: String) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: zone))
        return calendar
    }

    /// A take keeps the local day it was spoken on, so moving to another
    /// timezone later never moves it to another day.
    @Test func aTakeKeepsTheDayItWasSpokenOn() throws {
        // 2026-09-21 14:13 UTC is still the 21st in Los Angeles, already the
        // 22nd in Tokyo.
        let tokyo = HistoryEntry(at: at.addingTimeInterval(11 * 3600), durationMs: 1000, words: "one two", calendar: try calendar("Asia/Tokyo"))
        #expect(tokyo.day == "2026-09-22")
        #expect(tokyo.rankEvent.day == "2026-09-22")
        #expect(tokyo.rankEvent.words == 2)
        #expect(tokyo.rankEvent.at == 1_790_039_600_000)
        let encoded = try JSONEncoder().encode(tokyo)
        #expect(try JSONDecoder().decode(HistoryEntry.self, from: encoded).day == "2026-09-22")
    }

    /// A take kept before days were stored still counts, on the day it falls
    /// on now.
    @Test func anOlderTakeWithoutADayStillCounts() throws {
        let old = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","at":780000000,"durationMs":1000,"words":"one two three","wordCount":3,"retried":false}"#
        let entry = try JSONDecoder().decode(HistoryEntry.self, from: Data(old.utf8))
        #expect(entry.day == nil)
        #expect(entry.rankEvent.day == HistoryEntry.dayKey(entry.at))
        #expect(entry.rankEvent.words == 3)
    }

    @Test func theLadderAndTheBeltColorsLoad() throws {
        let rules = try BundledRules.journey()
        #expect(rules.ranks.ranks.first?.id == "none")
        #expect(rules.ranks.ranks.contains { $0.id == "blue" })
        #expect(rules.beltColors["white"]?.count == 7)
        #expect(rules.beltColors["red"] != nil)
    }
}

/// The belt this iPhone's takes have earned (IOS-017).
@Suite struct JourneyReportTests {
    let at = Date(timeIntervalSince1970: 1_790_000_000)

    /// The belt comes from this iPhone's takes: words and days both count,
    /// and deleting takes lowers it, as clearing history does on desktop.
    @Test func theBeltComesFromThisIPhonesTakes() throws {
        let rules = try BundledRules.journey()
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try #require(TimeZone(identifier: "UTC"))
        let words = Array(repeating: "word", count: 1300).joined(separator: " ")
        let entries = (0..<2).map { HistoryEntry(at: at.addingTimeInterval(Double($0) * 86_400), durationMs: 1000, words: words, calendar: utc) }
        let report = Journey.report(entries, rules: rules)
        #expect(report.rank.id == "white-1")
        #expect(report.totals.words == 2600 && report.totals.activeDays == 2)
        #expect(report.promotions.map(\.id) == ["white", "white-1"])
        #expect(report.next?.id == "white-2")
        #expect(Journey.report(Array(entries.prefix(1)), rules: rules).rank.id == "white")
        #expect(Journey.report([], rules: rules).rank.id == "none")
    }
}

@Suite struct JourneyCopyTests {
    /// A gate still open says how far along it is; one that holds says what
    /// you have and what it needed, never "7 of 6".
    @Test func gatesSayTheirNumbers() {
        #expect(JourneyCopy.words(GateProgress(have: 450, need: 600, pct: 0.75)) == "450 of 600 words")
        #expect(JourneyCopy.words(GateProgress(have: 700, need: 600, pct: 1)) == "700 words, 600 needed")
        #expect(JourneyCopy.days(GateProgress(have: 0, need: 1, pct: 0)) == "0 of 1 day you dictated")
        #expect(JourneyCopy.days(GateProgress(have: 2, need: 4, pct: 0.5)) == "2 of 4 days you dictated")
        #expect(JourneyCopy.days(GateProgress(have: 7, need: 6, pct: 1)) == "7 days you dictated, 6 needed")
        #expect(JourneyCopy.days(GateProgress(have: 1, need: 1, pct: 1)) == "1 day you dictated, 1 needed")
        #expect(JourneyCopy.level(3) == "Level 3")
    }

    @Test func everyLineFollowsTheWritingRules() throws {
        let rules = try BundledRules.journey()
        let lines = [JourneyCopy.top, JourneyCopy.devices, JourneyCopy.firstBelt(rules.ranks.ranks[1]), JourneyCopy.firstBelt(nil)]
        for line in lines {
            #expect(!line.contains("Murmur"))
            #expect(!line.contains("\u{2014}") && !line.contains(" - ") && !line.contains("--"))
        }
        #expect(JourneyCopy.firstBelt(rules.ranks.ranks[1]) == "Dictate 100 words to earn the white belt.")
    }
}
