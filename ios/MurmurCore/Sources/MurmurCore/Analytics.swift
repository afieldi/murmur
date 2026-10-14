// SPDX-License-Identifier: GPL-3.0-only
// The analytics (ios/prd.json IOS-021, more with IOS-022): desktop's
// src/shared/analytics.ts over the iPhone's takes, held to it by
// shared/analytics-vectors.json. For now, the share card's month.
import Foundation

/// One day's words and takes.
public struct DayTotal: Sendable, Hashable {
    public let day: String
    public let words: Int
    public let sessions: Int

    public init(day: String, words: Int, sessions: Int) {
        self.day = day
        self.words = words
        self.sessions = sessions
    }
}

public enum Analytics {
    /// The days the share card paints (desktop's CARD_DAYS).
    public static let cardDays = 30

    /// Words and takes for each of the last `count` days ending `today`
    /// (a yyyy-MM-dd key), oldest first, zero-filled, by each take's stored
    /// day, as desktop's dailyTotals counts them.
    public static func dailyTotals(_ events: [RankEvent], count: Int, today: String) -> [DayTotal] {
        guard count > 0 else { return [] }
        let keys = (0..<count).map { Paintings.shiftDay(today, $0 - (count - 1)) }
        var words: [String: Int] = [:]
        var sessions: [String: Int] = [:]
        let wanted = Set(keys)
        for event in events where wanted.contains(event.day) {
            words[event.day, default: 0] += event.words
            sessions[event.day, default: 0] += 1
        }
        return keys.map { DayTotal(day: $0, words: words[$0] ?? 0, sessions: sessions[$0] ?? 0) }
    }
}
