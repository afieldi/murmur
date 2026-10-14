// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Testing
@testable import murmur

/// Where notes live (IOS-023): murmur's own folder, out of backups, or one
/// you picked, such as an Obsidian vault, opened again from its bookmark.
@Suite struct NoteFolderTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "note-folder-\(UUID().uuidString)", directoryHint: .isDirectory)
    let defaults = UserDefaults(suiteName: "murmur.tests.\(UUID().uuidString)")!

    @Test func theFolderNeverWritesOutsideItself() {
        let folder = NoteStore(root: root)
        #expect(folder.url("../escape.md") == nil)
        #expect(folder.url("murmur/../../escape.md") == nil)
        #expect(folder.url("") == nil)
        #expect(folder.url("murmur/todo.md") != nil)
        #expect(throws: (any Error).self) { try folder.append("../escape.md", "out") }
    }

    @Test func murmursOwnFolderIsOutOfBackups() throws {
        let folder = NoteStore(root: root)
        try folder.append("murmur/inbox/2026-09-18.md", "one\n")
        try folder.append("murmur/inbox/2026-09-18.md", "two\n")
        #expect(folder.read("murmur/inbox/2026-09-18.md") == "one\ntwo\n")
        #expect(try root.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        #expect(folder.inboxDays(rules: try BundledRules.sorter()) == ["murmur/inbox/2026-09-18.md"])
    }

    @Test func aPickedFolderIsKeptAndOpenedAgain() throws {
        let vault = root.appending(path: "My Vault", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        let choice = NotesFolderChoice(defaults)
        try choice.pick(vault)
        #expect(choice.name == "My Vault")
        let store = choice.store()
        #expect(store.picked && !store.lost)
        #expect(store.root.standardizedFileURL.path == vault.standardizedFileURL.path)
        try store.append("murmur/inbox/2026-09-18.md", "one\n")
        try store.append("murmur/inbox/2026-09-18.md", "two\n")
        #expect(store.read("murmur/inbox/2026-09-18.md") == "one\ntwo\n")
        #expect(try String(contentsOf: vault.appending(path: "murmur/inbox/2026-09-18.md"), encoding: .utf8) == "one\ntwo\n")
    }

    /// A pick murmur can no longer open reads nothing and refuses every
    /// write, so a note from the keyboard is typed instead of lost.
    @Test func aLostFolderReadsNothingAndWritesNothing() throws {
        defaults.set(Data("not a bookmark".utf8), forKey: NotesFolderChoice.bookmarkKey)
        defaults.set("My Vault", forKey: NotesFolderChoice.nameKey)
        let lost = NotesFolderChoice(defaults).store(own: NoteStore(root: root))
        #expect(lost.lost)
        #expect(throws: (any Error).self) { try lost.append("murmur/inbox/2026-09-18.md", "one\n") }
        #expect(lost.read("murmur/inbox/2026-09-18.md") == nil)
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "murmur").path(percentEncoded: false)))
    }

    @Test func keepNotesInMurmurForgetsThePick() throws {
        let vault = root.appending(path: "vault", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        let choice = NotesFolderChoice(defaults)
        try choice.pick(vault)
        choice.forget()
        let own = NoteStore(root: root.appending(path: "own", directoryHint: .isDirectory))
        #expect(choice.name == nil)
        #expect(choice.store(own: own).root == own.root)
        #expect(!choice.store(own: own).picked)
    }
}
