// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Testing
@testable import murmur

@Suite struct MailboxTests {
    let mailbox = Mailbox(file: FileManager.default.temporaryDirectory.appending(path: "mailbox-\(UUID().uuidString).json"))
    let take = UUID()
    let at = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func anEmptyMailboxHoldsNothing() {
        #expect(mailbox.read() == nil)
        #expect(mailbox.claim() == nil)
    }

    @Test func whatTheAppWritesTheKeyboardReads() {
        let entry = MailboxEntry(take: take, phase: .working, words: nil, at: at)
        mailbox.write(entry)
        #expect(mailbox.read() == entry)
    }

    /// The first claim gets the words and clears them; a second gets
    /// nothing, so a take never inserts twice.
    @Test func wordsAreClaimedOnce() {
        mailbox.write(MailboxEntry(take: take, phase: .ready, words: "Send the invoice.", at: at))
        #expect(mailbox.claim(take) == "Send the invoice.")
        #expect(mailbox.claim(take) == nil)
        #expect(mailbox.claim() == nil)
        #expect(mailbox.read()?.words == nil)
        #expect(mailbox.read()?.phase == .ready)
    }

    @Test func aClaimForAnotherTakeGetsNothing() {
        mailbox.write(MailboxEntry(take: take, phase: .ready, words: "Send the invoice.", at: at))
        #expect(mailbox.claim(UUID()) == nil)
        #expect(mailbox.claim(take) == "Send the invoice.")
    }

    @Test func onlyReadyWordsAreClaimed() {
        mailbox.write(MailboxEntry(take: take, phase: .working, words: "not yet", at: at))
        #expect(mailbox.claim(take) == nil)
    }

    /// The real mailbox sits in the app group, where the keyboard can read it.
    @Test func theRealMailboxIsInTheAppGroup() throws {
        let shared = try #require(Mailbox.shared)
        #expect(shared.file.deletingLastPathComponent().standardizedFileURL == AppGroup.containerURL?.standardizedFileURL)
    }
}
