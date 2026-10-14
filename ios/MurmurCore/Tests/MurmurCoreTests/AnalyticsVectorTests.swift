// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Testing
@testable import MurmurCore

/// shared/analytics-vectors.json: desktop's analytics on fixed takes.
struct AnalyticsVectors: Decodable {
    struct Take: Decodable {
        let day: String
        let words: Int
    }

    struct Day: Decodable, Equatable {
        let day: String
        let words: Int
        let sessions: Int
    }

    struct DailyCase: Decodable, CustomTestStringConvertible {
        let name: String
        let today: String
        let count: Int
        let takes: [Take]
        let expect: [Day]

        var testDescription: String { name }
    }

    /// Desktop's CARD_DAYS: the days the share card paints.
    let cardDays: Int
    let dailyTotals: [DailyCase]

    static let file: AnalyticsVectors? = try? SharedData(directory: repoShared).decode(AnalyticsVectors.self, from: "analytics-vectors.json")
}

@Suite struct AnalyticsVectorTests {
    @Test func theVectorsLoad() throws {
        #expect(try #require(AnalyticsVectors.file).dailyTotals.count >= 5)
    }

    /// The card's month is desktop's length, so its strokes and its words
    /// ("in the last 30 days", painted by desktop's code) always agree.
    @Test func theCardsMonthIsDesktops() throws {
        #expect(try #require(AnalyticsVectors.file).cardDays == Analytics.cardDays)
    }

    @Test(arguments: AnalyticsVectors.file?.dailyTotals ?? [])
    func eachMonthTotalsAsOnDesktop(_ vector: AnalyticsVectors.DailyCase) {
        let events = vector.takes.map { RankEvent(at: 0, words: $0.words, day: $0.day) }
        let days = Analytics.dailyTotals(events, count: vector.count, today: vector.today)
        #expect(days.map { AnalyticsVectors.Day(day: $0.day, words: $0.words, sessions: $0.sessions) } == vector.expect)
    }

    /// No days asked for is no days, and a take with no day key is left out.
    @Test func edges() {
        #expect(Analytics.dailyTotals([], count: 0, today: "2026-10-13").isEmpty)
        let odd = [RankEvent(at: 0, words: 9, day: "")]
        #expect(Analytics.dailyTotals(odd, count: 2, today: "2026-10-13").map(\.words) == [0, 0])
    }
}
