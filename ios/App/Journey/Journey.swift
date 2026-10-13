// SPDX-License-Identifier: GPL-3.0-only
// Belts and stripes on iPhone (ios/prd.json IOS-017): the same ladder,
// gates, and math as desktop (shared/ranks.json, MurmurCore's Ranks), run
// over the takes this iPhone keeps in history. One Journey across devices
// comes with the murmur account (IOS-029).
import Foundation
import MurmurCore

enum Journey {
    /// Where this iPhone's takes have reached.
    static func report(_ entries: [HistoryEntry], rules: JourneyRules) -> ProgressReport {
        Ranks.progress(entries.map(\.rankEvent), spec: rules.ranks)
    }
}

/// What the Journey says.
enum JourneyCopy {
    static let title = "Journey"
    static let toward = "Toward"
    static let promotions = "Promotions"
    static let top = "You hold the highest belt practice earns."
    static let devices = "Belts count the takes on this iPhone. One Journey across your devices comes with the murmur account."

    static func level(_ level: Int) -> String {
        "Level \(level)"
    }

    /// Words toward the next belt; once the gate holds, what you have and
    /// what it needed.
    static func words(_ gate: GateProgress) -> String {
        gate.have >= gate.need
            ? "\(gate.have.formatted()) words, \(gate.need.formatted()) needed"
            : "\(gate.have.formatted()) of \(gate.need.formatted()) words"
    }

    static func days(_ gate: GateProgress) -> String {
        gate.have >= gate.need
            ? "\(gate.have.formatted()) \(gate.have == 1 ? "day" : "days") you dictated, \(gate.need.formatted()) needed"
            : "\(gate.have.formatted()) of \(gate.need.formatted()) \(gate.need == 1 ? "day" : "days") you dictated"
    }

    /// What earns the first belt, while there are no promotions yet.
    static func firstBelt(_ next: RankSpec?) -> String {
        guard let next, let words = next.words else { return "Your takes earn belts here." }
        return "Dictate \(words.formatted()) words to earn the \(next.label)."
    }

    static func promoted(_ at: Date) -> String {
        at.formatted(date: .abbreviated, time: .omitted)
    }
}
