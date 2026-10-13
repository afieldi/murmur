// SPDX-License-Identifier: GPL-3.0-only
// The dictation pad's decisions (ios/prd.json IOS-008), kept apart from
// its keys so the app's tests can hold them: where a take's words go, what
// the pad says, the space before the words, and the return key's name.
import Foundation
import UIKit

enum Pad {
    /// What the pad does with the newest mailbox entry.
    enum Reaction: Equatable {
        case none
        /// Show this line under the pill.
        case status(String)
        /// Insert this take's words at the cursor now.
        case insert(UUID)
        /// Offer Insert last: the words landed after you left the field.
        case offerInsertLast
    }

    /// What the pad says when the app does not answer, when another take
    /// is running, and when a take it was listening to stops answering.
    static let noAnswer = "Open murmur, then tap the pill again."
    static let busy = "murmur is busy with another take. Try again in a moment."
    static let stoppedAnswering = "murmur stopped answering. Open murmur to see why."
    /// While iOS opens murmur for the first take of a session (IOS-009), and
    /// when iOS will not.
    static let opening = "Opening murmur"
    /// Under the pill at rest (IOS-010): the pill itself carries no words.
    static let idleHint = "Tap the pill to talk"
    static let openRefused = "Open murmur to start"

    /// mine is the take this keyboard asked for, nil when it is not waiting
    /// on one; sameField is whether the cursor is still in the field the take
    /// began in; a keyboard that is not on screen does nothing, so it never
    /// takes words meant for the keyboard you are looking at.
    static func react(to entry: MailboxEntry?, mine: UUID?, sameField: Bool, visible: Bool) -> Reaction {
        guard visible, let entry else { return .none }
        let ours = entry.take == mine
        switch entry.phase {
        case .ready where entry.words != nil:
            return ours && sameField ? .insert(entry.take) : .offerInsertLast
        case .ready:
            return .none
        case .listening where ours:
            return .status("Listening")
        case .working where ours:
            return .status("Working")
        case .nothing where ours:
            return .status("Heard nothing")
        case .failed where ours:
            return .status("That take did not work. Open murmur to see why.")
        default:
            return .none
        }
    }

    /// The words, with a space first when the text before the cursor needs
    /// one: after a word or a sentence's end, never after a space, a line
    /// break, or an opening bracket or quote, and never before punctuation.
    static func spaced(_ words: String, after before: String?) -> String {
        guard let last = before?.last, !last.isWhitespace, !"([{\"'\u{201C}\u{2018}/".contains(last),
              let first = words.first, !",.;:!?)]}".contains(first)
        else { return words }
        return " " + words
    }

    /// The pill's stage after a refresh: the take's own while one is waited
    /// on; nil (leave it) while how the last take ended still shows; rest
    /// otherwise, so a keyboard that comes back with no take never keeps an
    /// old stage, least of all Recording.
    static func stage(waiting: Bool, phase: MailboxEntry.Phase?, ending: Bool) -> PillStage? {
        if waiting { return PillStage(phase) }
        return ending ? nil : .idle
    }

    /// The take this keyboard is waiting on, kept in the keyboard's own
    /// defaults: opening murmur closes the keyboard, and the one you swipe
    /// back to is a new one that has to know the take is its own.
    struct Waiting: Codable, Equatable {
        let take: UUID
        /// Started by opening murmur, so the words land in the field you come
        /// back to, and leaving the keyboard does not cancel it.
        let opened: Bool
        /// The field the take began in; for an opened take, the field the
        /// keyboard came back to.
        var field: UUID?
        let at: Date
        /// An opened take that a keyboard you came back to has taken over.
        private(set) var adopted = false

        /// A take waited on longer than this is let go: its words, if any,
        /// wait as Insert last.
        static let life: TimeInterval = 10 * 60
        static let key = "waitingTake"

        static func load(from defaults: UserDefaults, now: Date = .now) -> Waiting? {
            guard let data = defaults.data(forKey: key), let waiting = try? JSONDecoder().decode(Waiting.self, from: data),
                  now.timeIntervalSince(waiting.at) < life
            else { return nil }
            return waiting
        }

        static func save(_ waiting: Waiting?, to defaults: UserDefaults) {
            if let waiting, let data = try? JSONEncoder().encode(waiting) {
                defaults.set(data, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        /// Whether the cursor is in the take's field. An opened take adopts
        /// the first field the keyboard comes back to.
        func sameField(as current: UUID?) -> Bool {
            field == nil || field == current
        }

        /// The keyboard you came back to from murmur takes the opened take
        /// over, in the field it is in.
        mutating func adopt(_ current: UUID?) {
            field = current
            adopted = true
        }

        /// Whether leaving the keyboard drops this take: one still starting or
        /// listening is dropped, except on the trip to murmur an opened take
        /// is for. Once taken over, an opened take is dropped like any other,
        /// so a take you walked away from never runs on unattended.
        func cancelsOnLeave(phase: MailboxEntry.Phase?) -> Bool {
            (!opened || adopted) && (phase == nil || phase == .listening)
        }
    }

    /// The return key's name, following the field's return key type.
    static func returnTitle(_ type: UIReturnKeyType) -> String {
        switch type {
        case .go: "Go"
        case .google, .yahoo, .search: "Search"
        case .join: "Join"
        case .next: "Next"
        case .route: "Route"
        case .send: "Send"
        case .done: "Done"
        case .emergencyCall: "Emergency call"
        case .continue: "Continue"
        default: "Return"
        }
    }
}
