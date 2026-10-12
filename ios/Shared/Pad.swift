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
