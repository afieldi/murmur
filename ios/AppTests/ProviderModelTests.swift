// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import MurmurCore
import Testing
@testable import murmur

@MainActor @Suite struct ProviderModelTests {
    let catalog: ProviderCatalog
    let defaults: UserDefaults
    let ring = MemoryKeyRing()
    let groq = "https://api.groq.com/openai/v1"

    init() throws {
        catalog = try BundledRules.catalog()
        defaults = try #require(UserDefaults(suiteName: "murmur.tests.\(UUID().uuidString)"))
    }

    func model(status: Int = 200) -> ProviderModel {
        ProviderModel(catalog: catalog, store: ConnectionStore(defaults: defaults), ring: ring, send: { request in
            (Data(), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        })
    }

    func preset(_ id: String) throws -> ProviderCatalog.Provider {
        try #require(catalog.providers.first { $0.id == id })
    }

    @Test func startsOnGroqWithCleanupRidingIt() {
        let model = model()
        #expect(model.transcriptionPreset?.id == "groq")
        #expect(model.settings.transcription.sttModel == "whisper-large-v3-turbo")
        #expect(model.transcriptionKey.baseUrl == groq)
        #expect(model.cleanupSharesKey)
    }

    @Test func aPresetFillsItsAddressAndFirstModels() throws {
        let model = model()
        model.chooseTranscription(try preset("openai"))
        #expect(model.settings.transcription.baseUrl == "https://api.openai.com/v1")
        #expect(model.settings.transcription.sttModel == "gpt-transcribe")
        #expect(model.settings.transcription.llmModel == "gpt-5.6-luna")
    }

    @Test func customClearsTheAddressForTyping() {
        let model = model()
        model.chooseTranscription(nil)
        #expect(model.transcriptionPreset == nil)
        #expect(model.settings.transcription.baseUrl == "")
        #expect(model.transcriptionKey.addressProblem == "Enter the provider's base URL.")
    }

    @Test func switchingProvidersNeverAsksForAKeyTwice() throws {
        let model = model()
        model.transcriptionKey.draft = "gsk_groqgroq1111"
        model.transcriptionKey.save()
        model.chooseTranscription(try preset("openai"))
        #expect(model.transcriptionKey.masked == nil)
        model.transcriptionKey.draft = "sk-openaiopenai2222"
        model.transcriptionKey.save()
        model.chooseTranscription(try preset("groq"))
        #expect(model.transcriptionKey.masked == "••••1111")
        model.chooseTranscription(try preset("openai"))
        #expect(model.transcriptionKey.masked == "••••2222")
    }

    @Test func savingTrimsThePasteAndClearsTheField() throws {
        let model = model()
        model.transcriptionKey.draft = "  gsk_groqgroq1111\n"
        model.transcriptionKey.save()
        #expect(try ring.key(for: groq)?.secret == "gsk_groqgroq1111")
        #expect(model.transcriptionKey.draft == "")
        #expect(model.transcriptionKey.masked == "••••1111")
    }

    /// The note is gentle: a key with the wrong prefix still saves.
    @Test func aWrongPrefixGetsANoteAndStillSaves() throws {
        let model = model()
        model.transcriptionKey.draft = "sk-notgroq1111"
        #expect(model.transcriptionKey.note == .expected(prefixes: ["gsk_"], provider: "Groq"))
        #expect(model.transcriptionKey.canSave)
        model.transcriptionKey.save()
        #expect(model.transcriptionKey.masked == "••••1111")
    }

    @Test(arguments: [(200, ConnectionVerdict.works), (401, .keyRejected(status: 401))])
    func testAnswersInline(_ status: Int, _ verdict: ConnectionVerdict) async throws {
        let model = model(status: status)
        model.transcriptionKey.draft = "gsk_groqgroq1111"
        model.transcriptionKey.save()
        await model.transcriptionKey.runTest()
        #expect(model.transcriptionKey.test == .done(verdict))
    }

    @Test func noKeyMeansNoTest() async {
        let model = model()
        #expect(!model.transcriptionKey.canTest)
        await model.transcriptionKey.runTest()
        #expect(model.transcriptionKey.test == .idle)
    }

    /// A verdict earned at one address never vouches for another.
    @Test func switchingProvidersClearsTheVerdict() async throws {
        let model = model()
        model.transcriptionKey.draft = "gsk_groqgroq1111"
        model.transcriptionKey.save()
        await model.transcriptionKey.runTest()
        model.chooseTranscription(try preset("openai"))
        #expect(model.transcriptionKey.test == .idle)
    }

    @Test func separateCleanupGetsItsOwnKeyUnlessItSharesTheAddress() throws {
        let model = model()
        model.setSeparateCleanup(true)
        model.chooseCleanup(try preset("groq"))
        #expect(model.cleanupSharesKey)
        model.chooseCleanup(try preset("deepseek"))
        #expect(!model.cleanupSharesKey)
        #expect(model.cleanupKey.baseUrl == "https://api.deepseek.com")
        #expect(model.settings.cleanupModel == "deepseek-flash")
    }

    @Test func theCleanupModelFollowsWhereCleanupRuns() throws {
        let model = model()
        model.setCleanupModel("openai/gpt-oss-20b")
        #expect(model.settings.transcription.llmModel == "openai/gpt-oss-20b")
        model.setSeparateCleanup(true)
        model.chooseCleanup(try preset("deepseek"))
        model.setCleanupModel("deepseek-other")
        #expect(model.settings.cleanup.llmModel == "deepseek-other")
        #expect(model.settings.transcription.llmModel == "openai/gpt-oss-20b")
    }

    /// An answer that lands after the person moved to another provider
    /// is dropped, so it never vouches for the new one.
    @Test func aLateAnswerNeverLandsOnAnotherProvider() async throws {
        let gate = AsyncStream<Void>.makeStream()
        let model = ProviderModel(catalog: catalog, store: ConnectionStore(defaults: defaults), ring: ring, send: { request in
            for await _ in gate.stream { break }
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        model.transcriptionKey.draft = "gsk_groqgroq1111"
        model.transcriptionKey.save()
        let running = Task { await model.transcriptionKey.runTest() }
        for _ in 0..<100 where model.transcriptionKey.test != .testing { await Task.yield() }
        #expect(model.transcriptionKey.test == .testing)
        model.chooseTranscription(try preset("openai"))
        gate.continuation.yield()
        gate.continuation.finish()
        await running.value
        #expect(model.transcriptionKey.test == .idle)
    }

    @Test func unreadableSavedChoicesFallBackToDefaults() {
        defaults.set(Data("not json".utf8), forKey: ConnectionStore.defaultsKey)
        #expect(model().transcriptionPreset?.id == "groq")
    }

    @Test func choicesSurviveARelaunch() throws {
        model().chooseTranscription(try preset("mistral"))
        #expect(model().transcriptionPreset?.id == "mistral")
    }

    @Test func aKeyNeverReachesTheDefaults() throws {
        let model = model()
        model.transcriptionKey.draft = "gsk_groqgroq1111"
        model.transcriptionKey.save()
        model.chooseTranscription(try preset("openai"))
        #expect(!"\(defaults.dictionaryRepresentation())".contains("gsk_groqgroq1111"))
    }

    @Test func aKeychainFailureIsSaidPlainly() {
        let slot = KeySlot(baseUrl: groq, catalog: catalog, ring: FailingRing(), send: { _ in throw URLError(.cancelled) })
        #expect(slot.failure == "murmur could not reach the Keychain (code -25308). Try again.")
        slot.draft = "gsk_groqgroq1111"
        slot.save()
        #expect(slot.draft == "gsk_groqgroq1111")
    }
}

/// A Keychain that refuses everything, as a locked phone can.
private struct FailingRing: KeyRing {
    func key(for baseUrl: String) throws -> APIKey? { throw KeychainError.status(-25308) }
    func save(_ key: APIKey, for baseUrl: String) throws { throw KeychainError.status(-25308) }
    func remove(for baseUrl: String) throws { throw KeychainError.status(-25308) }
}
