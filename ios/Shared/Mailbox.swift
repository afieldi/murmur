// SPDX-License-Identifier: GPL-3.0-only
// The mailbox (ios/prd.json IOS-008): small files in the app group shared
// by the app and the keyboard. The keyboard leaves its request for a take,
// with its own id; the app tells the keyboard how that take is going and,
// once it is done, its words. The keyboard claims the words once, which
// clears them, so a take never inserts twice and the shared drawer never
// keeps words longer than it must. Reads and writes are coordinated, since
// the app and the keyboard are two processes.
import Foundation

struct MailboxEntry: Codable, Equatable, Sendable {
    enum Phase: String, Codable, Sendable {
        case listening, working, ready, nothing, failed
    }

    /// The id the keyboard asked with, so each keyboard knows its own take.
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

    /// Where the keyboard leaves its request, beside the mailbox.
    var requestFile: URL {
        file.deletingLastPathComponent().appending(path: file.deletingPathExtension().lastPathComponent + "-request.json")
    }

    private struct Request: Codable {
        let take: UUID
        let at: Date
    }

    func read() -> MailboxEntry? {
        var entry: MailboxEntry?
        coordinate(file, writing: false) { url in
            entry = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(MailboxEntry.self, from: $0) }
        }
        return entry
    }

    func write(_ entry: MailboxEntry) {
        coordinate(file, writing: true) { url in
            try? JSONEncoder().encode(entry).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    /// The take's words, once: the first claim gets them and clears them,
    /// and every later claim gets nil.
    func claim(_ take: UUID? = nil) -> String? {
        var words: String?
        coordinate(file, writing: true) { url in
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

    /// Drops words still waiting to be typed (Insert last) when you delete
    /// them in murmur (IOS-012): the ones given, or any with nil. A take
    /// still running is left alone.
    func forget(_ words: Set<String>?) {
        coordinate(file, writing: true) { url in
            guard let data = try? Data(contentsOf: url),
                  var entry = try? JSONDecoder().decode(MailboxEntry.self, from: data),
                  entry.phase == .ready, let waiting = entry.words,
                  words?.contains(waiting) ?? true
            else { return }
            entry.words = nil
            try? JSONEncoder().encode(entry).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    /// The keyboard asks for a take with its own id, just before it signals
    /// start.
    func ask(_ take: UUID, at: Date = .now) {
        coordinate(requestFile, writing: true) { url in
            try? JSONEncoder().encode(Request(take: take, at: at)).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    /// The take the keyboard asked for, once, and only while the ask is
    /// fresh: a start that waited (murmur was not running) is dropped
    /// instead of recording a take no keyboard is waiting on.
    func answer(within seconds: TimeInterval, now: Date = .now) -> UUID? {
        var take: UUID?
        coordinate(requestFile, writing: true) { url in
            defer { try? FileManager.default.removeItem(at: url) }
            guard let data = try? Data(contentsOf: url),
                  let request = try? JSONDecoder().decode(Request.self, from: data),
                  abs(now.timeIntervalSince(request.at)) <= seconds
            else { return }
            take = request.take
        }
        return take
    }

    private func coordinate(_ url: URL, writing: Bool, _ body: (URL) -> Void) {
        let coordinator = NSFileCoordinator()
        var error: NSError?
        if writing {
            coordinator.coordinate(writingItemAt: url, options: .forMerging, error: &error, byAccessor: body)
        } else {
            coordinator.coordinate(readingItemAt: url, options: [], error: &error, byAccessor: body)
        }
    }
}
