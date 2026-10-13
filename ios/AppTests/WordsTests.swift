// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import MurmurCore
import Testing
@testable import murmur

@MainActor @Suite struct WordsModelTests {
    let defaults: UserDefaults

    init() throws {
        defaults = try #require(UserDefaults(suiteName: "murmur.tests.\(UUID().uuidString)"))
    }

    func model() -> WordsModel { WordsModel(store: CleanupStore(defaults: defaults)) }

    /// A word is saved trimmed, kept across launches, and refused when
    /// either side is empty.
    @Test func aWordIsSavedAndKept() {
        let words = model()
        #expect(words.saveWord(DictionaryEntry(from: "  la broy ", to: " LaBroi ")))
        #expect(!words.saveWord(DictionaryEntry(from: "eze", to: "  ")))
        #expect(!words.saveWord(DictionaryEntry(from: " ", to: "Eze")))
        #expect(words.dictionary == [DictionaryEntry(from: "la broy", to: "LaBroi")])
        #expect(model().dictionary == [DictionaryEntry(from: "la broy", to: "LaBroi")])
        #expect(CleanupStore(defaults: defaults).load().dictionary.count == 1)
    }

    /// Editing replaces the entry in place, and a new word murmur already
    /// listens for replaces that one: a word is never listed twice.
    @Test func editingReplacesAndNothingIsListedTwice() {
        let words = model()
        words.saveWord(DictionaryEntry(from: "la broy", to: "Labroi"))
        words.saveWord(DictionaryEntry(from: "eze media", to: "Eze Media"))
        words.saveWord(DictionaryEntry(from: "la broy", to: "LaBroi"), at: 0)
        #expect(words.dictionary.map(\.to) == ["LaBroi", "Eze Media"])
        words.saveWord(DictionaryEntry(from: "LA BROY", to: "LaBroi W."))
        #expect(words.dictionary.map(\.to) == ["LaBroi W.", "Eze Media"])
        words.deleteWord(at: 0)
        #expect(words.dictionary.map(\.to) == ["Eze Media"])
        #expect(model().dictionary.map(\.to) == ["Eze Media"])
    }

    @Test func expansionsWorkTheSameWay() {
        let words = model()
        #expect(words.saveExpansion(ExpansionEntry(trigger: " my address ", text: " 1 Main Street, Springfield ")))
        #expect(!words.saveExpansion(ExpansionEntry(trigger: "sig", text: "")))
        words.saveExpansion(ExpansionEntry(trigger: "My Address", text: "2 Oak Lane"))
        #expect(words.expansions == [ExpansionEntry(trigger: "My Address", text: "2 Oak Lane")])
        words.deleteExpansion(at: 0)
        #expect(model().expansions.isEmpty)
    }

    /// Search finds either side, whatever the case, and keeps each entry's
    /// place in the full list.
    @Test func searchFindsEitherSide() {
        let words = model()
        words.saveWord(DictionaryEntry(from: "la broy", to: "LaBroi"))
        words.saveWord(DictionaryEntry(from: "eze media", to: "Eze Media"))
        words.saveExpansion(ExpansionEntry(trigger: "my address", text: "1 Main Street"))
        #expect(words.words(matching: "media").map(\.index) == [1])
        #expect(words.words(matching: "BROY").map(\.entry.to) == ["LaBroi"])
        #expect(words.words(matching: "").count == 2)
        #expect(words.expansions(matching: "main").map(\.index) == [0])
        #expect(words.expansions(matching: "nothing").isEmpty)
    }

    /// What the screen saves is what every take runs through: the word on
    /// the raw text with its casing kept, and the expansion last.
    @Test func aTakesWordsRunThroughBoth() async throws {
        let words = model()
        words.saveWord(DictionaryEntry(from: "la broy", to: "LaBroi"))
        words.saveExpansion(ExpansionEntry(trigger: "my address", text: "1 Main Street, Springfield"))
        var settings = CleanupStore(defaults: defaults).load()
        settings.polish = false
        let rules = try BundledRules.takeRules().cleanup
        let finished = await Cleanup.finish("la broy lives at my address", settings: settings, rules: rules, connection: nil, send: { _ in throw URLError(.notConnectedToInternet) })
        #expect(finished.contains("LaBroi lives at 1 Main Street, Springfield"))
    }
}
