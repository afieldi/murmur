// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Testing
import UIKit
@testable import murmur

@Suite struct PadTests {
    let take = UUID()
    let started = Date(timeIntervalSince1970: 1_790_000_000)

    func entry(_ phase: MailboxEntry.Phase, words: String? = nil, at: Date? = nil) -> MailboxEntry {
        MailboxEntry(take: take, phase: phase, words: words, at: at ?? started.addingTimeInterval(0.2))
    }

    @Test func wordsForThisTakeInTheSameFieldAreInserted() {
        #expect(Pad.react(to: entry(.ready, words: "hi"), startedAt: started, sameField: true) == .insert(take))
    }

    /// You left the field before the words landed: Insert last.
    @Test func wordsAfterYouLeftTheFieldWaitAsInsertLast() {
        #expect(Pad.react(to: entry(.ready, words: "hi"), startedAt: started, sameField: false) == .offerInsertLast)
        // The keyboard came back later, not waiting on anything.
        #expect(Pad.react(to: entry(.ready, words: "hi"), startedAt: nil, sameField: true) == .offerInsertLast)
    }

    @Test func claimedWordsOfferNothing() {
        #expect(Pad.react(to: entry(.ready), startedAt: started, sameField: true) == .none)
        #expect(Pad.react(to: nil, startedAt: started, sameField: true) == .none)
    }

    @Test func thisTakesProgressIsShown() {
        #expect(Pad.react(to: entry(.listening), startedAt: started, sameField: true) == .status("Listening"))
        #expect(Pad.react(to: entry(.working), startedAt: started, sameField: true) == .status("Working"))
        #expect(Pad.react(to: entry(.nothing), startedAt: started, sameField: true) == .status("Heard nothing"))
        #expect(Pad.react(to: entry(.failed), startedAt: started, sameField: true) == .status("That take did not work. Open murmur to see why."))
    }

    /// An older take's progress never shows as this one's.
    @Test func anOlderTakeIsNotThisOne() {
        let old = entry(.listening, at: started.addingTimeInterval(-60))
        #expect(Pad.react(to: old, startedAt: started, sameField: true) == .none)
        #expect(Pad.react(to: entry(.listening), startedAt: nil, sameField: true) == .none)
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
