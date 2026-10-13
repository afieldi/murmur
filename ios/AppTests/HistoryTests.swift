// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import MurmurCore
import Testing
@testable import murmur

@Suite struct HistoryStoreTests {
    let store = HistoryStore(file: FileManager.default.temporaryDirectory.appending(path: "history-\(UUID().uuidString)", directoryHint: .isDirectory).appending(path: "history.jsonl"))
    let start = Date(timeIntervalSince1970: 1_790_000_000)

    func entry(_ words: String, _ minutes: Double) -> HistoryEntry {
        HistoryEntry(at: start.addingTimeInterval(minutes * 60), durationMs: 2_400, words: words)
    }

    /// Takes read back newest first, with their words, time, length, and
    /// word count.
    @Test func takesReadBackNewestFirst() throws {
        #expect(store.list().isEmpty)
        try store.append(entry("First take.", 0))
        try store.append(entry("Second take here.", 1))
        let entries = store.list()
        #expect(entries.map(\.words) == ["Second take here.", "First take."])
        #expect(entries[0].wordCount == 3)
        #expect(entries[0].durationMs == 2_400)
        #expect(entries[1].at == start)
    }

    @Test func oneTakeDeletesAndClearAllEmpties() throws {
        let keep = entry("Keep me.", 0)
        let drop = entry("Drop me.", 1)
        try store.append(keep)
        try store.append(drop)
        try store.remove(drop.id)
        #expect(store.list() == [keep])
        try store.append(entry("Another.", 2))
        try store.clear()
        #expect(store.list().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: store.file.path))
    }

    /// History never leaves the phone: out of iCloud backups, and writable
    /// after first unlock, as a take can land with the phone locked.
    @Test func historyStaysOnThePhone() throws {
        try store.append(entry("Private words.", 0))
        let folder = store.file.deletingLastPathComponent()
        #expect(try folder.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        let protection = try store.file.resourceValues(forKeys: [.fileProtectionKey]).fileProtection
        #expect(protection == .completeUntilFirstUserAuthentication)
        #expect(!store.file.path.contains("Group Containers") && !store.file.path.contains("AppGroup"))
    }

    /// A damaged line costs that line, never the rest.
    @Test func aDamagedLineIsSkipped() throws {
        try store.append(entry("Before.", 0))
        let handle = try FileHandle(forWritingTo: store.file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{not a take}\n".utf8))
        try handle.close()
        try store.append(entry("After.", 1))
        #expect(store.list().map(\.words) == ["After.", "Before."])
    }

    /// The real history sits in the app's own container.
    @Test func theRealHistoryIsTheAppsOwn() {
        #expect(HistoryStore.standard.file.path.hasPrefix(URL.applicationSupportDirectory.path))
    }
}

@MainActor @Suite struct HistoryModelTests {
    let store = HistoryStore(file: FileManager.default.temporaryDirectory.appending(path: "history-model-\(UUID().uuidString).jsonl"))

    @Test func theModelKeepsTheScreenCurrent() {
        let history = History(store: store)
        let first = HistoryEntry(at: .now, durationMs: 1_000, words: "One.")
        let second = HistoryEntry(at: .now, durationMs: 1_000, words: "Two.")
        history.add(first)
        history.add(second)
        #expect(history.entries.map(\.words) == ["Two.", "One."])
        history.delete(second.id)
        #expect(history.entries == [first])
        #expect(History(store: store).entries == [first])
        history.clear()
        #expect(history.entries.isEmpty)
        #expect(History(store: store).entries.isEmpty)
    }
}
