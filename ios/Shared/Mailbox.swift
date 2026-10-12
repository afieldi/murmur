// SPDX-License-Identifier: GPL-3.0-only
// The mailbox (ios/prd.json IOS-008): one small file in the app group
// where the app tells the keyboard how the newest take is going and,
// once it is done, its words. The keyboard claims the words once, which
// clears them, so a take never inserts twice and the shared drawer never
// keeps words longer than it must. Reads and writes are coordinated, since
// the app and the keyboard are two processes.
import Foundation

struct MailboxEntry: Codable, Equatable, Sendable {
    enum Phase: String, Codable, Sendable {
        case listening, working, ready, nothing, failed
    }

    /// Which take this is, so a late answer never lands on a newer take.
    let take: UUID
    var phase: Phase
    /// The words, only while ready and not yet claimed.
    var words: String?
    let at: Date
}

struct Mailbox: Sendable {
    let file: URL

    /// mailbox.json in the app group, or nil without the entitlement.
    static var shared: Mailbox? {
        AppGroup.containerURL.map { Mailbox(file: $0.appending(path: "mailbox.json")) }
    }

    func read() -> MailboxEntry? {
        var entry: MailboxEntry?
        coordinate(writing: false) { url in
            entry = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(MailboxEntry.self, from: $0) }
        }
        return entry
    }

    func write(_ entry: MailboxEntry) {
        coordinate(writing: true) { url in
            try? JSONEncoder().encode(entry).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    /// The take's words, once: the first claim gets them and clears them,
    /// and every later claim gets nil.
    func claim(_ take: UUID? = nil) -> String? {
        var words: String?
        coordinate(writing: true) { url in
            guard let data = try? Data(contentsOf: url),
                  var entry = try? JSONDecoder().decode(MailboxEntry.self, from: data),
                  take == nil || entry.take == take,
                  entry.phase == .ready, let ready = entry.words
            else { return }
            words = ready
            entry.words = nil
            try? JSONEncoder().encode(entry).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        return words
    }

    private func coordinate(writing: Bool, _ body: (URL) -> Void) {
        let coordinator = NSFileCoordinator()
        var error: NSError?
        if writing {
            coordinator.coordinate(writingItemAt: file, options: .forMerging, error: &error, byAccessor: body)
        } else {
            coordinator.coordinate(readingItemAt: file, options: [], error: &error, byAccessor: body)
        }
    }
}
