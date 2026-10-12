// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import MurmurCore
import Synchronization
import Testing
@testable import murmur

/// A provider that answers each request with the next of its replies,
/// then the last, and remembers what it was sent.
final class FakeProvider: Sendable {
    let replies: Mutex<[(Int, String)]>
    let sent = Mutex<[URLRequest]>([])

    init(_ replies: [(Int, String)]) {
        self.replies = Mutex(replies)
    }

    static func says(_ words: String) -> FakeProvider { FakeProvider([(200, #"{"text":"\#(words)"}"#)]) }

    var requests: [URLRequest] { sent.withLock { $0 } }

    func answer(_ replies: [(Int, String)]) { self.replies.withLock { $0 = replies } }

    var send: ConnectionTest.Send {
        { request in
            self.sent.withLock { $0.append(request) }
            let (status, body) = self.replies.withLock { replies in replies.count > 1 ? replies.removeFirst() : replies[0] }
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
    }
}

@MainActor @Suite struct TakeModelTests {
    let groq = "https://api.groq.com/openai/v1"
    let catalog: ProviderCatalog
    let rules: TakeRules
    let defaults: UserDefaults
    let ring = MemoryKeyRing()
    let store = WaitingStore(directory: FileManager.default.temporaryDirectory.appending(path: "murmur-takes-\(UUID().uuidString)", directoryHint: .isDirectory))
    let microphone = ScriptedMicrophone(samples: ScriptedMicrophone.tone)
    let sink = Sink()

    /// What a take copied, and the time it reads.
    @MainActor final class Sink {
        var copied: [String] = []
        var now = Date(timeIntervalSince1970: 1_790_000_000)
    }

    init() throws {
        catalog = try BundledRules.catalog()
        rules = try BundledRules.takeRules()
        defaults = try #require(UserDefaults(suiteName: "murmur.tests.\(UUID().uuidString)"))
        try ring.save(try #require(APIKey("gsk_groqgroq1111")), for: groq)
    }

    func model(_ provider: FakeProvider) -> TakeModel {
        TakeModel(
            microphone: microphone, store: store, rules: rules, catalog: catalog,
            connections: ConnectionStore(defaults: defaults), ring: ring, send: provider.send,
            copy: { [sink] text in sink.copied.append(text) },
            now: { [sink] in sink.now }
        )
    }

    func pass(_ seconds: TimeInterval) {
        sink.now = sink.now.addingTimeInterval(seconds)
    }

    func take(_ model: TakeModel) async {
        await model.start()
        pass(2)
        await model.stop()
    }

    @Test func theFirstTakeAsksForTheMicrophone() async {
        let model = model(.says("hello"))
        await model.start()
        #expect(microphone.asked == 1)
        #expect(model.state == .recording(since: Date(timeIntervalSince1970: 1_790_000_000)))
    }

    @Test func noMicrophoneSaysHowToTurnItOn() async {
        microphone.allowed = false
        let model = model(.says("hello"))
        await model.start()
        #expect(model.state == .micOff)
        #expect(microphone.started == 0)
    }

    @Test func aMicrophoneThatWillNotStartSaysSo() async {
        microphone.startError = MicrophoneError.noInput
        let model = model(.says("hello"))
        await model.start()
        #expect(model.state == .micFailed)
    }

    @Test func aSpokenTakeComesBackAsWords() async throws {
        let provider = FakeProvider.says("Send the invoice tomorrow.")
        let model = model(provider)
        await take(model)
        #expect(model.state == .words("Send the invoice tomorrow."))
        let request = try #require(provider.requests.first)
        #expect(provider.requests.count == 1)
        #expect(request.url?.absoluteString == groq + "/audio/transcriptions")
        #expect(String(decoding: try #require(request.httpBody), as: UTF8.self).contains("whisper-large-v3-turbo"))
        #expect(model.waiting.isEmpty)
    }

    @Test func silenceIsNeverSent() async {
        microphone.samples = ScriptedMicrophone.silence
        let provider = FakeProvider.says("Thank you.")
        let model = model(provider)
        await take(model)
        #expect(model.state == .heardNothing(sent: false))
        #expect(provider.requests.isEmpty)
        #expect(model.waiting.isEmpty)
    }

    @Test func aPhraseInventedOnSilenceIsHeardNothing() async {
        let model = model(.says("Thank you."))
        await take(model)
        #expect(model.state == .heardNothing(sent: true))
        #expect(model.waiting.isEmpty)
    }

    @Test func aFailedTakeWaitsWithItsAudio() async throws {
        let provider = FakeProvider([(503, "{}")])
        let model = model(provider)
        await take(model)
        let failure = TakeFailure(kind: "server", detail: "http 503")
        #expect(model.state == .failed(failure, saved: true))
        let waiting = try #require(model.waiting.first)
        #expect(model.waiting.count == 1)
        #expect(waiting.failure == failure)
        #expect(waiting.startedAt == Date(timeIntervalSince1970: 1_790_000_000))
        #expect(try store.audio(waiting.id) == TakeAudio.upload(ScriptedMicrophone.tone, gate: rules.gate))
    }

    @Test func noKeyWaitsWithoutSending() async {
        try? ring.remove(for: groq)
        let provider = FakeProvider.says("hello")
        let model = model(provider)
        await take(model)
        #expect(model.state == .failed(.noKey, saved: true))
        #expect(provider.requests.isEmpty)
        #expect(model.waiting.first?.failure == .noKey)
    }

    @Test func aRetryDeliversTheWordsThenDeletesTheAudio() async throws {
        let provider = FakeProvider([(503, "{}")])
        let model = model(provider)
        await take(model)
        provider.answer([(200, #"{"text":"Send the invoice tomorrow."}"#)])
        await model.retry(model.waiting.map(\.id))
        #expect(model.state == .words("Send the invoice tomorrow."))
        #expect(sink.copied == ["Send the invoice tomorrow."])
        #expect(model.waiting.isEmpty)
        #expect(store.list().isEmpty)
        #expect(model.message == "Done: the words are above and on your clipboard.")
    }

    /// Retry all keeps every take's words, not only the last.
    @Test func retryAllKeepsEveryTakesWords() async throws {
        let provider = FakeProvider([(503, "{}")])
        let model = model(provider)
        await take(model)
        pass(5)
        await take(model)
        #expect(model.waiting.count == 2)
        provider.answer([(200, #"{"text":"First."}"#), (200, #"{"text":"Second."}"#)])
        await model.retry(model.waiting.map(\.id))
        #expect(model.state == .words("First.\n\nSecond."))
        #expect(sink.copied.last == "First.\n\nSecond.")
        #expect(model.waiting.isEmpty)
        #expect(model.message == "Done: 2 takes. Their words are above and on your clipboard.")
    }

    @Test func aRetryThatFailsAgainUpdatesTheReason() async throws {
        let provider = FakeProvider([(503, "{}")])
        let model = model(provider)
        await take(model)
        provider.answer([(401, "{}")])
        await model.retry(model.waiting.map(\.id))
        #expect(model.waiting.first?.failure == TakeFailure(kind: "auth", detail: "http 401"))
        #expect(model.message == "Still could not transcribe. The reason is updated below; the audio stays until you retry or discard it.")
        #expect(sink.copied.isEmpty)
    }

    @Test func aRetryThatHearsNothingSaysSo() async throws {
        let provider = FakeProvider([(503, "{}")])
        let model = model(provider)
        await take(model)
        provider.answer([(200, #"{"text":"Thank you."}"#)])
        await model.retry(model.waiting.map(\.id))
        #expect(model.waiting.first?.failure == .noSpeech)
    }

    /// Discard turns into delete audio?, and the second tap of a quick
    /// double tap never deletes.
    @Test func discardAsksFirstAndIgnoresADoubleTap() async throws {
        let model = model(FakeProvider([(503, "{}")]))
        await take(model)
        let id = try #require(model.waiting.first?.id)
        model.discard(id)
        #expect(model.armed == id)
        pass(0.2)
        model.discard(id)
        #expect(model.waiting.count == 1)
        pass(0.4)
        model.discard(id)
        #expect(model.waiting.isEmpty)
        #expect(model.armed == nil)
    }

    @Test func leavingMidTakeKeepsAndSendsNothing() async {
        let provider = FakeProvider.says("hello")
        let model = model(provider)
        await model.start()
        model.cancel()
        #expect(model.state == .idle)
        #expect(provider.requests.isEmpty)
        #expect(model.waiting.isEmpty)
    }

    @Test func aRetryWaitsWhileATakeRecords() async {
        let provider = FakeProvider([(503, "{}")])
        let model = model(provider)
        await take(model)
        await model.start()
        await model.retry(model.waiting.map(\.id))
        #expect(provider.requests.count == 2)
        #expect(model.isRecording)
    }

    /// The take reads today's provider choice each time.
    @Test func aTakeUsesTheChosenProvider() async throws {
        var settings = ConnectionStore(defaults: defaults).load(catalog: catalog)
        settings.transcription.baseUrl = "https://api.openai.com/v1"
        settings.transcription.sttModel = "gpt-transcribe"
        ConnectionStore(defaults: defaults).save(settings)
        try ring.save(try #require(APIKey("sk-openaiopenai2222")), for: "https://api.openai.com/v1")
        let provider = FakeProvider.says("hello there")
        let model = model(provider)
        await take(model)
        let request = try #require(provider.requests.first)
        #expect(request.url?.absoluteString == "https://api.openai.com/v1/audio/transcriptions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-openaiopenai2222")
    }
}
