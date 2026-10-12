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

    /// startedAt is when this keyboard asked for a take, nil when it is not
    /// waiting on one; sameField is whether the cursor is still in the field
    /// the take began in.
    static func react(to entry: MailboxEntry?, startedAt: Date?, sameField: Bool) -> Reaction {
        guard let entry else { return .none }
        let ours = startedAt.map { entry.at >= $0.addingTimeInterval(-1) } ?? false
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
