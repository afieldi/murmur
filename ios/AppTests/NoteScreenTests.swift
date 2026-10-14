// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import MurmurCore
import Testing
@testable import murmur

/// New note (IOS-023) keeps a take that just landed, once.
@MainActor @Suite struct NoteScreenTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "note-screens-\(UUID().uuidString)", directoryHint: .isDirectory)
    let at = Date(timeIntervalSince1970: 1_789_727_520)

    @Test func newNoteSavesOnlyATakeThatJustLanded() throws {
        let folder = NoteStore(root: root.appending(path: "notes", directoryHint: .isDirectory))
        let notes = Notes(
            folder: folder, rules: try BundledRules.sorter(), stateFile: NotesStateFile(file: root.appending(path: "state.json")),
            sortOn: { false }, ask: { nil }, timeZone: { TimeZone(identifier: "UTC")! }
        )
        #expect(NoteTake.keep(from: .transcribing, to: .words("Call the dentist."), notes: notes, at: at) == NoteTake.Kept(words: "Call the dentist.", place: "inbox"))
        #expect(NoteTake.keep(from: .idle, to: .words("Call the dentist."), notes: notes, at: at) == nil)
        #expect(NoteTake.keep(from: .transcribing, to: .heardNothing(sent: true), notes: notes, at: at) == nil)
        #expect(folder.read("murmur/inbox/2026-09-18.md") == "## 10:32\n\nCall the dentist.\n\n")
    }
}
