// SPDX-License-Identifier: GPL-3.0-only
// The dictionary and expansions (ios/prd.json IOS-013), kept in the
// cleanup settings that every take already runs through (IOS-007): a word
// with the spelling and casing you want, and a short trigger that becomes
// longer text. Adding, editing, searching, and deleting happen here.
import Foundation
import MurmurCore
import Observation

@Observable @MainActor final class WordsModel {
    private(set) var dictionary: [DictionaryEntry]
    private(set) var expansions: [ExpansionEntry]
    @ObservationIgnored private let store: CleanupStore

    init(store: CleanupStore) {
        self.store = store
        let settings = store.load()
        dictionary = settings.dictionary
        expansions = settings.expansions
    }

    /// Saves a word: both sides trimmed and not empty. Editing replaces the
    /// entry at that place; a new word that murmur already listens for
    /// replaces that one, so a word is never in the list twice. False when
    /// a side is empty.
    @discardableResult
    func saveWord(_ entry: DictionaryEntry, at index: Int? = nil) -> Bool {
        guard let entry = Self.clean(entry) else { return false }
        var next = dictionary
        if let index, next.indices.contains(index) {
            next[index] = entry
        } else if let same = next.firstIndex(where: { $0.from.caseInsensitiveCompare(entry.from) == .orderedSame }) {
            next[same] = entry
        } else {
            next.append(entry)
        }
        dictionary = next
        persist()
        return true
    }

    func deleteWord(at index: Int) {
        guard dictionary.indices.contains(index) else { return }
        dictionary.remove(at: index)
        persist()
    }

    /// Saves an expansion the same way, matching on its trigger.
    @discardableResult
    func saveExpansion(_ entry: ExpansionEntry, at index: Int? = nil) -> Bool {
        let trigger = entry.trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trigger.isEmpty, !text.isEmpty else { return false }
        let clean = ExpansionEntry(trigger: trigger, text: text)
        var next = expansions
        if let index, next.indices.contains(index) {
            next[index] = clean
        } else if let same = next.firstIndex(where: { $0.trigger.caseInsensitiveCompare(trigger) == .orderedSame }) {
            next[same] = clean
        } else {
            next.append(clean)
        }
        expansions = next
        persist()
        return true
    }

    func deleteExpansion(at index: Int) {
        guard expansions.indices.contains(index) else { return }
        expansions.remove(at: index)
        persist()
    }

    /// The words whose either side holds the search, with their places.
    func words(matching query: String) -> [(index: Int, entry: DictionaryEntry)] {
        let query = query.trimmingCharacters(in: .whitespaces)
        return dictionary.enumerated()
            .filter { query.isEmpty || $0.element.from.localizedCaseInsensitiveContains(query) || $0.element.to.localizedCaseInsensitiveContains(query) }
            .map { ($0.offset, $0.element) }
    }

    func expansions(matching query: String) -> [(index: Int, entry: ExpansionEntry)] {
        let query = query.trimmingCharacters(in: .whitespaces)
        return expansions.enumerated()
            .filter { query.isEmpty || $0.element.trigger.localizedCaseInsensitiveContains(query) || $0.element.text.localizedCaseInsensitiveContains(query) }
            .map { ($0.offset, $0.element) }
    }

    private static func clean(_ entry: DictionaryEntry) -> DictionaryEntry? {
        let from = entry.from.trimmingCharacters(in: .whitespacesAndNewlines)
        let to = entry.to.trimmingCharacters(in: .whitespacesAndNewlines)
        return from.isEmpty || to.isEmpty ? nil : DictionaryEntry(from: from, to: to)
    }

    private func persist() {
        var settings = store.load()
        settings.dictionary = dictionary
        settings.expansions = expansions
        store.save(settings)
    }
}
