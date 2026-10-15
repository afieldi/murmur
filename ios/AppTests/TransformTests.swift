// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import MurmurCore
import Testing
@testable import murmur

extension TakeModelTests {
    /// An instruction gets the dictionary and nothing else, as desktop's
    /// transform, and counts toward nothing, so history never sees it.
    @Test func anInstructionIsHeardAsSaidAndNotKept() async throws {
        CleanupStore(defaults: defaults).save(CleanupSettings(polish: false, dictionary: [DictionaryEntry(from: "jon", to: "John")]))
        let model = model(.says("um make it shorter for jon"))
        await model.start(as: .instruction)
        pass(2)
        await model.stop()
        #expect(model.state == .words("um make it shorter for John"))
        #expect(sink.kept.isEmpty)
        // The same words as an ordinary take are cleaned up and kept.
        await model.start()
        pass(2)
        await model.stop()
        #expect(model.state != .words("um make it shorter for John"))
        #expect(sink.kept.count == 1)
    }
}

@Suite struct TransformPadTests {
    @Test func aFailureSaysItsOwnLine() {
        let take = UUID()
        let entry = MailboxEntry(take: take, phase: .failed, words: nil, at: .now, line: "The selection is as it was.")
        #expect(Pad.react(to: entry, mine: take, sameField: true, visible: true) == .status("The selection is as it was."))
        let plain = MailboxEntry(take: take, phase: .failed, words: nil, at: .now)
        #expect(Pad.react(to: plain, mine: take, sameField: true, visible: true) == .status("That take did not work. Open murmur to see why."))
    }

    @Test func aRewriteGoesInOnlyOverItsOwnSelection() {
        let rewrite = Pad.Waiting(take: UUID(), opened: false, field: nil, at: .now, original: "old words", selected: "old words")
        #expect(rewrite.replaces("old words"))
        #expect(!rewrite.replaces("other words"))
        #expect(!rewrite.replaces(nil))
        #expect(!rewrite.replaces(""))
        let words = Pad.Waiting(take: UUID(), opened: false, field: nil, at: .now)
        #expect(!words.replaces("old words"))
        // Taken whole from the clipboard, it still goes in over the
        // shortened selection the keyboard saw.
        let copied = Pad.Waiting(take: UUID(), opened: false, field: nil, at: .now, original: "One. Two. Three.", selected: "One. Three.")
        #expect(copied.replaces("One. Three."))
        #expect(!copied.replaces("One. Two. Three."))
    }

    /// iOS gives a keyboard only the first and last sentences of a longer
    /// selection, so only one sentence of modest length is trusted whole.
    @Test(arguments: [
        ("Call the dentist tomorrow.", true),
        ("Call the dentist tomorrow", true),
        ("  Call the dentist.  ", true),
        ("Wait... what?", false),
        ("Call Dr. Smith today.", false),
        ("Call the dentist. Email Bob.", false),
        ("milk\neggs", false),
        ("Is it done?Yes", true),
        ("第一。第二", true),
        ("第一。 第二", false),
        (String(repeating: "a", count: 300), true),
        (String(repeating: "a", count: 301), false)
    ])
    func onlyOneSentenceIsTrustedWhole(_ selected: String, _ whole: Bool) {
        #expect(Pad.isWhole(selected) == whole)
    }

    @Test func theClipboardGivesTheWholeSelectionOnlyWhenItHoldsIt() {
        let shortened = "This is text0. This is text7. 1234567890"
        let full = "This is text0. This is text1. This is text2. This is text7. 1234567890"
        #expect(Pad.whole(shortened, clipboard: full) == full)
        #expect(Pad.whole(full, clipboard: full) == full)
        #expect(Pad.whole(shortened, clipboard: nil) == nil)
        #expect(Pad.whole(shortened, clipboard: "") == nil)
        #expect(Pad.whole(shortened, clipboard: "Something else entirely, copied earlier.") == nil)
        // The clipboard must open with the first sentence and close with the last.
        #expect(Pad.whole(shortened, clipboard: "This is text0. This is text1. Then more.") == nil)
        #expect(Pad.whole(shortened, clipboard: "Before. This is text0. This is text1. This is text7. 1234567890") == nil)
        // Shorter than what the keyboard saw cannot be the whole of it.
        #expect(Pad.whole(shortened, clipboard: "This is text0. 1234567890") == nil)
        #expect(Pad.pieces("One.\n\nTwo!  Three") == ["One.", "Two!", "Three"])
    }

    /// A take a keyboard before transforms saved still reads.
    @Test func anOlderWaitingTakeStillReads() throws {
        let defaults = try #require(UserDefaults(suiteName: "murmur.tests.\(UUID().uuidString)"))
        let take = UUID()
        let older = #"{"take":"\#(take.uuidString)","opened":false,"at":\#(Date.now.timeIntervalSinceReferenceDate),"adopted":false}"#
        defaults.set(Data(older.utf8), forKey: Pad.Waiting.key)
        let waiting = try #require(Pad.Waiting.load(from: defaults))
        #expect(waiting.take == take)
        #expect(waiting.original == nil)
    }

    @Test func aTransformsAskCarriesItsSelection() throws {
        let mailbox = Mailbox(file: FileManager.default.temporaryDirectory.appending(path: "ask-\(UUID().uuidString).json"))
        let take = UUID()
        mailbox.ask(take, selection: "old words")
        #expect(mailbox.answer(within: 3) == TakeAsk(take: take, note: false, selection: "old words"))
        mailbox.ask(take)
        #expect(mailbox.answer(within: 3)?.selection == nil)
    }

    @Test func theLogNamesHowEachWentNeverTheWords() {
        #expect(ActivityEvent.transform(kept: nil).line == "transform rewritten")
        #expect(ActivityEvent.transform(kept: "preamble line").line == "transform kept reason=preamble-line")
        #expect(ActivityEvent.transform(kept: "http 401").line == "transform kept reason=http-401")
    }
}
