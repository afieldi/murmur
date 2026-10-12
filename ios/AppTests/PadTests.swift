// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Testing
import UIKit
@testable import murmur

@Suite struct PadTests {
    let take = UUID()

    func entry(_ phase: MailboxEntry.Phase, words: String? = nil, take: UUID? = nil) -> MailboxEntry {
        MailboxEntry(take: take ?? self.take, phase: phase, words: words, at: Date(timeIntervalSince1970: 1_790_000_000))
    }

    func react(_ entry: MailboxEntry?, mine: UUID?, sameField: Bool = true, visible: Bool = true) -> Pad.Reaction {
        Pad.react(to: entry, mine: mine, sameField: sameField, visible: visible)
    }

    @Test func wordsForThisTakeInTheSameFieldAreInserted() {
        #expect(react(entry(.ready, words: "hi"), mine: take) == .insert(take))
    }

    /// You left the field before the words landed: Insert last.
    @Test func wordsAfterYouLeftTheFieldWaitAsInsertLast() {
        #expect(react(entry(.ready, words: "hi"), mine: take, sameField: false) == .offerInsertLast)
        // The keyboard came back later, not waiting on anything.
        #expect(react(entry(.ready, words: "hi"), mine: nil) == .offerInsertLast)
    }

    /// A keyboard that is not on screen does nothing, so it never takes
    /// words meant for the keyboard you are looking at.
    @Test func aKeyboardOffScreenDoesNothing() {
        #expect(react(entry(.ready, words: "hi"), mine: take, visible: false) == .none)
        #expect(react(entry(.listening), mine: take, visible: false) == .none)
    }

    @Test func claimedWordsOfferNothing() {
        #expect(react(entry(.ready), mine: take) == .none)
        #expect(react(nil, mine: take) == .none)
    }

    @Test func thisTakesProgressIsShown() {
        #expect(react(entry(.listening), mine: take) == .status("Listening"))
        #expect(react(entry(.working), mine: take) == .status("Working"))
        #expect(react(entry(.nothing), mine: take) == .status("Heard nothing"))
        #expect(react(entry(.failed), mine: take) == .status("That take did not work. Open murmur to see why."))
    }

    /// Another take's progress never shows as this one's, matched by the id
    /// the keyboard asked with.
    @Test func anotherTakeIsNotThisOne() {
        #expect(react(entry(.listening, take: UUID()), mine: take) == .none)
        #expect(react(entry(.listening), mine: nil) == .none)
        #expect(react(entry(.ready, words: "hi", take: UUID()), mine: take) == .offerInsertLast)
    }

    @Test func thePadsOwnLinesReadPlainly() {
        for line in [Pad.noAnswer, Pad.busy, Pad.stoppedAnswering] {
            #expect(!line.contains("Murmur"))
        }
    }

    @Test(arguments: [
        (nil as String?, "hello", "hello"),
        ("", "hello", "hello"),
        ("Hi", "there", " there"),
        ("Done.", "Next", " Next"),
        ("Hi ", "there", "there"),
        ("line\n", "next", "next"),
        ("(", "aside", "aside"),
        ("\u{201C}", "quote", "quote"),
        ("word", ", and", ", and"),
        ("word", ".", ".")
    ])
    func aSpaceGoesFirstOnlyWhenNeeded(_ before: String?, _ words: String, _ inserted: String) {
        #expect(Pad.spaced(words, after: before) == inserted)
    }

    @Test func returnFollowsTheField() {
        #expect(Pad.returnTitle(.default) == "Return")
        #expect(Pad.returnTitle(.send) == "Send")
        #expect(Pad.returnTitle(.search) == "Search")
        #expect(Pad.returnTitle(.go) == "Go")
        #expect(Pad.returnTitle(.done) == "Done")
    }
}
