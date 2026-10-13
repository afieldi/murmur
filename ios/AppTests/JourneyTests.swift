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
