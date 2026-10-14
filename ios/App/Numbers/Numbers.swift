// SPDX-License-Identifier: GPL-3.0-only
// Your numbers (ios/prd.json IOS-022): desktop's analytics, time back, and
// recap over this iPhone's takes (MurmurCore's Analytics, TimeBack, and
// Recap, held to desktop by shared/analytics-vectors.json). Time back is
// counted against typing with your thumbs. The daily recap is one local
// notification at the time you pick, off until you turn it on.
import Foundation
import MurmurCore
import UserNotifications

/// Time back and recap choices, kept on this iPhone.
struct NumbersSettings: Equatable {
    static let wpmKey = "numbers.typingWpm"
    static let recapKey = "numbers.recap"
    static let hourKey = "numbers.recapHour"
    static let minuteKey = "numbers.recapMinute"

    /// Words a minute your thumbs type, clamped to 10 through 200.
    var typingWpm: Double
    var recapOn: Bool
    /// When the recap arrives, desktop's 17:30 until you pick.
    var recapHour: Int
    var recapMinute: Int

    static func load(_ defaults: UserDefaults = .standard) -> NumbersSettings {
        let wpm = defaults.object(forKey: wpmKey) as? Double
        let hour = defaults.object(forKey: hourKey) as? Int ?? 17
        let minute = defaults.object(forKey: minuteKey) as? Int ?? 30
        return NumbersSettings(
            typingWpm: TimeBack.clamp(wpm),
            recapOn: defaults.bool(forKey: recapKey),
            recapHour: (0...23).contains(hour) ? hour : 17,
            recapMinute: (0...59).contains(minute) ? minute : 30
        )
    }

    func save(_ defaults: UserDefaults = .standard) {
        defaults.set(TimeBack.clamp(typingWpm), forKey: Self.wpmKey)
        defaults.set(recapOn, forKey: Self.recapKey)
        defaults.set(recapHour, forKey: Self.hourKey)
        defaults.set(recapMinute, forKey: Self.minuteKey)
    }
}

/// What the numbers are priced and dated with, read once from the bundle.
struct NumbersRules: Sendable {
    let catalog: ProviderCatalog
    let rates: Rates

    static let live: NumbersRules? = (try? BundledRules.catalog()).map { NumbersRules(catalog: $0, rates: Rates($0)) }

    /// The models your takes ran through: the estimate prices those.
    func models(_ defaults: UserDefaults = .standard) -> (stt: String, llm: String) {
        let connection = ConnectionStore(defaults: defaults).load(catalog: catalog)
        return (connection.transcription.sttModel, connection.cleanupModel)
    }
}

enum Numbers {
    /// The takes as the numbers see them, each on the day it stored.
    static func usage(_ entries: [HistoryEntry]) -> [UsageEvent] {
        entries.map { entry in
            UsageEvent(day: entry.rankEvent.day, words: entry.wordCount, durationMs: entry.durationMs)
        }
    }

    /// Everything the numbers screen, Home, and the recap show, as of `today`.
    static func summary(_ entries: [HistoryEntry], rules: NumbersRules, settings: NumbersSettings, today: String = HistoryEntry.dayKey(.now), defaults: UserDefaults = .standard) -> AnalyticsSummary {
        let models = rules.models(defaults)
        return Analytics.aggregate(usage(entries), rates: rules.rates, today: today, sttModel: models.stt, llmModel: models.llm, typingWpm: settings.typingWpm)
    }

    /// Desktop's money: under a cent reads as under a cent.
    static func money(_ usd: Double) -> String {
        if usd > 0, usd < 0.01 { return "<$0.01" }
        return String(format: "$%.2f", usd)
    }

    /// "Oct 3", for a day key.
    static func prettyDay(_ day: String) -> String {
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let month = Int(day.dropFirst(5).prefix(2)) ?? 1
        let date = Int(day.suffix(2)) ?? 1
        return "\(months[max(0, min(11, month - 1))]) \(date)"
    }
}

/// The recap's pending notifications: one for each of the next days at the
/// recap time, today's with today's numbers so far and the rest quiet until
/// their takes land. Every take, every return to murmur, and every change of
/// setting plans them again, so a recap always says the day as it stood at
/// the last take, and a week away still gets its quiet recaps.
struct RecapPlan: Equatable {
    struct Item: Equatable {
        /// The request's id: the prefix and the day.
        let id: String
        let day: String
        let fire: DateComponents
        let body: String
    }

    static let prefix = "murmur.recap."
    /// How many days ahead are kept pending.
    static let days = 7

    let items: [Item]

    /// The plan for these takes at `now`, or nothing with the recap off.
    static func plan(_ entries: [HistoryEntry], rules: NumbersRules, settings: NumbersSettings, now: Date = .now, calendar: Calendar = .current, locale: Locale = .current, defaults: UserDefaults = .standard) -> RecapPlan {
        guard settings.recapOn else { return RecapPlan(items: []) }
        let today = HistoryEntry.dayKey(now, calendar: calendar)
        let summary = Numbers.summary(entries, rules: rules, settings: settings, today: today, defaults: defaults)
        var items: [Item] = []
        for offset in 0..<days {
            let day = Paintings.shiftDay(today, offset)
            let parts = day.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3 else { continue }
            let fire = DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: parts[0], month: parts[1], day: parts[2], hour: settings.recapHour, minute: settings.recapMinute)
            guard let at = calendar.date(from: fire), at > now else { continue }
            let body = offset == 0 ? Recap.body(RecapSummary(summary.today), locale: locale) : RecapWords.iPhone.quiet
            items.append(Item(id: prefix + day, day: day, fire: fire, body: body))
        }
        return RecapPlan(items: items)
    }
}

/// The notifications themselves, through the system's notification center.
@MainActor enum RecapNotifications {
    static let title = "murmur recap"

    /// Lays the plan down: every pending recap replaced, none with the recap off.
    static func apply(_ plan: RecapPlan, center: UNUserNotificationCenter = .current()) async {
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(RecapPlan.prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        guard !plan.items.isEmpty else { return }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        for item in plan.items {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = item.body
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: item.fire, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: trigger))
        }
    }

    /// Plans the recap again from the takes kept now.
    static func refresh(_ entries: [HistoryEntry]) async {
        guard let rules = NumbersRules.live else { return }
        await apply(RecapPlan.plan(entries, rules: rules, settings: .load()))
    }

    /// Asks once, when the recap is turned on: true when it may arrive.
    static func ask(center: UNUserNotificationCenter = .current()) async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Today's recap, two seconds from now, to see how it reads.
    static func sendNow(_ entries: [HistoryEntry], center: UNUserNotificationCenter = .current()) async {
        guard let rules = NumbersRules.live else { return }
        let summary = Numbers.summary(entries, rules: rules, settings: .load())
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = Recap.body(RecapSummary(summary.today))
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: RecapPlan.prefix + "now", content: content, trigger: trigger))
    }
}

/// The numbers' words.
enum NumbersCopy {
    static let title = "Your numbers"
    static let row = "Your numbers"
    static let emptyTitle = "No numbers yet."
    static let emptyLine = "Your words, minutes, and time back count from your first dictation."
    static let thisMonth = "This month"
    static let lastDays = "Last 14 days"
    static let wall = "Getting active"
    static let lifetime = "Lifetime"
    static let minutesDictated = "Minutes dictated"
    static let minutes = "Minutes"
    static let words = "Words"
    static let takes = "Takes"
    static let timeBack = "Time back"
    static let cost = "Est. cost"
    static let avgWpm = "Avg wpm"
    static let less = "less"
    static let more = "more"
    static let wallNote = "Every mark is a day; deeper paint is more words. Show up and the wall fills."

    /// The estimate's footnote, with the date murmur's rates were checked.
    static func ratesNote(_ checked: String) -> String {
        "Estimates at the rates murmur knows for your models (checked \(checked)), assuming the cleanup pass runs. Your provider bills you directly; murmur never sees it."
    }

    static func wallTotal(_ words: Int) -> String {
        "\(words.formatted(.number)) words lifetime"
    }

    /// What VoiceOver reads for the fourteen days.
    static func chartLabel(_ days: [DayUsage]) -> String {
        "Words per day, last 14 days: " + days.map { "\(Numbers.prettyDay($0.day)), \($0.words.formatted(.number))" }.joined(separator: "; ")
    }

    /// What VoiceOver reads for the wall.
    static func wallLabel(_ wall: Heatmap) -> String {
        let active = wall.days.filter { $0.words > 0 }
        guard let busiest = active.max(by: { $0.words < $1.words || ($0.words == $1.words && $0.day > $1.day) }) else {
            return "Activity wall: no dictation lifetime yet"
        }
        return "Activity wall: \(wall.totalWords.formatted(.number)) words lifetime, on \(active.count.formatted(.number)) days; the busiest was \(Numbers.prettyDay(busiest.day)) with \(busiest.words.formatted(.number)) words"
    }

    // Home.
    static let backToday = "Back today"
    static let noTypical = "Today is measured against your typical day once you have \(Analytics.typicalMinDays) days of dictation in the last four weeks, not counting today."
    static let zeroTypical = "Your typical day has no time back yet, so today stands on its own."

    static func spans(month: Double, lifetime: Double) -> String {
        "\(TimeBack.format(month)) this month · \(TimeBack.format(lifetime)) lifetime"
    }

    /// The line under today's time back.
    static func typical(_ summary: AnalyticsSummary) -> String {
        guard let typical = summary.typicalBack else { return noTypical }
        guard typical > 0 else { return zeroTypical }
        return TimeBack.typicalLine(share: Analytics.typicalShare(today: summary.today.minutesBack, typical: typical), typical: typical)
    }

    // Settings.
    static let screen = "Time back and recap"
    static let typing = "Typing speed"
    static func wpm(_ value: Double) -> String { "\(Int(value)) words a minute" }
    static let typingFooter = "Time back counts the minutes you would have spent typing your words with your thumbs, minus the time you spent speaking. 36 words a minute is the average on a phone across 37,370 people (Palin and others, MobileHCI 2019, checked 2026-10-13). Set your own speed if you type faster or slower; every day is counted again at the new speed."
    static let recap = "Daily recap"
    static let recapTime = "Time"
    static let recapFooter = "One notification a day at the time you pick: the day's takes, minutes, words, and time back. Off until you turn it on; murmur asks to send notifications only then."
    static let denied = "Notifications are off for murmur, so the recap cannot arrive. Turn them on in Settings."
    static let openSettings = "Open Settings"
    static let sendNow = "Send one now"
}
