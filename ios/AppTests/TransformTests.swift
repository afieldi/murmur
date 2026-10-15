// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import MurmurCore
import Testing
@testable import murmur

extension KeyboardBridgeTests {
    static let selected = "The meeting ran long, and nobody could say why it had been called."
    static let shorter = "The meeting ran long for no clear reason."

    /// A rewriter on a stand-in model: what it was sent, and what it answers.
    func rewriter(_ reply: FakeProvider, connected: Bool = true, events: Events? = nil) throws -> Rewriter {
        let connection = PolishConnection(baseUrl: "https://edit.example/v1", model: "edit-model", key: try #require(APIKey("sk-test")))
        return Rewriter(
            rules: try BundledRules.transform(), connection: { connected ? connection : nil }, send: reply.send,
            log: { event in events?.list.append(event) }
        )
    }

    @MainActor final class Events {
        var list: [ActivityEvent] = []
    }

    static func chat(_ content: String) -> FakeProvider {
        let body = try! JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": content]]]])
        return FakeProvider([(200, String(decoding: body, as: UTF8.self))])
    }

    /// Transform (IOS-024): the take is the instruction, the selection goes
    /// with it, and the keyboard gets the rewrite with the original beside it.
    @Test func aTransformTakeComesBackRewritten() async throws {
        let model = try model(.says("make this shorter"))
        let chat = Self.chat(Self.shorter)
        let events = Events()
        let bridge = KeyboardBridge(model: model, mailbox: mailbox, announce: { _ in }, rewriter: try rewriter(chat, events: events))
        bridge.listen()
        let take = UUID()
        mailbox.ask(take, selection: Self.selected)
        bridge.hear(.start)
        try await waitUntilRecording(model)
        bridge.hear(.stop)
        let ready = try #require(try await waitFor(.ready))
        #expect(ready.take == take)
        #expect(ready.words == Self.shorter)
        #expect(ready.original == Self.selected)
        let sent = try #require(chat.requests.first?.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        let messages = try #require(sent["messages"] as? [[String: String]])
        #expect(messages.count == 3)
        #expect(messages[1]["content"]?.contains(Self.selected) == true)
        #expect(messages[2]["content"] == "INSTRUCTION\nmake this shorter")
        #expect(events.list == [.transform(kept: nil)])
        // The rewrite goes in once; then Insert last brings back the original.
        #expect(mailbox.claim(take) == Self.shorter)
        #expect(mailbox.claim() == Self.selected)
        #expect(mailbox.claim() == nil)
    }

    /// On any failure the selection stays as it was, and the keyboard says so.
    @Test func aRewriteThatFailsLeavesTheSelection() async throws {
        let model = try model(.says("make this shorter"))
        let events = Events()
        let bridge = KeyboardBridge(model: model, mailbox: mailbox, announce: { _ in }, rewriter: try rewriter(FakeProvider([(500, "{}")]), events: events))
        bridge.listen()
        mailbox.ask(UUID(), selection: Self.selected)
        bridge.hear(.start)
        try await waitUntilRecording(model)
        bridge.hear(.stop)
        let failed = try #require(try await waitFor(.failed))
        #expect(failed.line == TransformCopy.kept)
        #expect(failed.words == nil)
        #expect(mailbox.claim() == nil)
        #expect(events.list == [.transform(kept: "http 500")])
    }

    /// Without a key nothing is heard: the take ends before it listens.
    @Test func noConnectionEndsTheTakeBeforeItListens() async throws {
        let model = try model(.says("make this shorter"))
        let bridge = KeyboardBridge(model: model, mailbox: mailbox, announce: { _ in }, rewriter: try rewriter(Self.chat("x"), connected: false))
        bridge.listen()
        mailbox.ask(UUID(), selection: Self.selected)
        bridge.hear(.start)
        #expect(mailbox.read()?.phase == .failed)
        #expect(mailbox.read()?.line == TransformCopy.noConnection)
        #expect(microphone.started == 0)
        #expect(!model.isRecording)
    }

    /// A selection past the shared limit is never sent, and nothing is heard.
    @Test func aSelectionTooLongEndsTheTakeBeforeItListens() async throws {
        let model = try model(.says("make this shorter"))
        let chat = Self.chat("x")
        let bridge = KeyboardBridge(model: model, mailbox: mailbox, announce: { _ in }, rewriter: try rewriter(chat))
        bridge.listen()
        mailbox.ask(UUID(), selection: String(repeating: "a", count: 8_001))
        bridge.hear(.start)
        #expect(mailbox.read()?.phase == .failed)
        #expect(mailbox.read()?.line == TransformCopy.tooLong(8_001, max: 8_000))
        #expect(microphone.started == 0)
        #expect(chat.requests.isEmpty)
    }

    /// A take asked with no selection is typed as always, never rewritten.
    @Test func aTakeWithoutASelectionIsTyped() async throws {
        let model = try model(.says("Send the invoice."))
        let chat = Self.chat("x")
        let bridge = KeyboardBridge(model: model, mailbox: mailbox, announce: { _ in }, rewriter: try rewriter(chat))
        bridge.listen()
        start(bridge)
        try await waitUntilRecording(model)
        bridge.hear(.stop)
        let ready = try #require(try await waitFor(.ready))
        #expect(ready.words == "Send the invoice.")
        #expect(ready.original == nil)
        #expect(chat.requests.isEmpty)
    }
}

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
