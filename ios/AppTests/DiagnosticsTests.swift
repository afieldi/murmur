// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import MurmurCore
import Testing
@testable import murmur

@MainActor @Suite struct DiagnosticsReportTests {
    let groq = "https://api.groq.com/openai/v1"
    let catalog: ProviderCatalog
    let defaults: UserDefaults
    let ring = MemoryKeyRing()
    let log = scratchLog()
    let waiting = WaitingStore(directory: FileManager.default.temporaryDirectory.appending(path: "report-takes-\(UUID().uuidString)", directoryHint: .isDirectory))
    let history = HistoryStore(file: FileManager.default.temporaryDirectory.appending(path: "report-history-\(UUID().uuidString).jsonl"))
    let mailbox = Mailbox(file: FileManager.default.temporaryDirectory.appending(path: "report-mailbox-\(UUID().uuidString).json"))
    let at = Date(timeIntervalSince1970: 1_790_000_000)

    init() throws {
        catalog = try BundledRules.catalog()
        defaults = try #require(UserDefaults(suiteName: "murmur.tests.\(UUID().uuidString)"))
    }

    func facts(keyboard: KeyboardReport? = nil, session: SessionState = .off) -> DiagnosticsFacts {
        DiagnosticsReport.facts(
            catalog: catalog, connections: ConnectionStore(defaults: defaults), cleanup: CleanupStore(defaults: defaults), ring: ring,
            log: log, waiting: waiting, history: history, defaults: defaults, keyboard: keyboard, session: session,
            mailbox: mailbox, pill: PillLook(style: .bars), now: at
        )
    }

    /// The report says what the app is, what the phone is, how the keyboard
    /// and session stand, settings as names and counts, and the recent log.
    @Test func theReportSaysWhatHelps() throws {
        try ring.save(try #require(APIKey("gsk_groqgroq1111")), for: groq)
        var settings = CleanupStore(defaults: defaults).load()
        settings.dictionary = [DictionaryEntry(from: "la broy", to: "LaBroi"), DictionaryEntry(from: "eze", to: "Eze")]
        settings.expansions = [ExpansionEntry(trigger: "my address", text: "1 Main Street")]
        CleanupStore(defaults: defaults).save(settings)
        defaults.set(60, forKey: Session.lengthKey)
        log.write(.words(count: 3, retried: false), at: at)
        let text = DiagnosticsReport.text(facts(keyboard: KeyboardReport(fullAccess: true, at: at), session: SessionState(until: at.addingTimeInterval(60))))
        for line in [
            "murmur diagnostics report", "generated: 2026-09-21T14:13:20Z", "version: ", "system: iOS ", "device: ",
            "keyboard: reported with Full Access, last 2026-09-21T14:13:20Z", "session: 60 minutes, running",
            "transcription: Groq, model whisper-large-v3-turbo", "keySaved: yes", "dictionaryEntries: 2", "expansionEntries: 1",
            "waitingTakes: 0", "historyTakes: 0", "pill: bars", "2026-09-21T14:13:20Z take words count=3"
        ] {
            #expect(text.contains(line), "missing \(line)")
        }
        #expect(!text.contains("LaBroi") && !text.contains("la broy") && !text.contains("Main Street") && !text.contains("gsk_"))
    }

    /// A custom address is never written, only that it is custom.
    @Test func aCustomAddressIsNeverWritten() {
        var connection = ConnectionStore(defaults: defaults).load(catalog: catalog)
        connection.transcription.baseUrl = "https://speech.private.example.com/v1"
        ConnectionStore(defaults: defaults).save(connection)
        let text = DiagnosticsReport.text(facts())
        #expect(text.contains("transcription: custom, model "))
        #expect(!text.contains("private.example.com"))
        #expect(text.contains("keySaved: no"))
        #expect(text.contains("keyboard: no report yet"))
        #expect(text.contains("session: 15 minutes, off"))
        #expect(text.contains("(nothing yet)"))
    }

    /// The report notes the keyboard's last take first, so it is included.
    @Test func theKeyboardsLastTakeIsIncluded() {
        mailbox.write(MailboxEntry(take: UUID(), phase: .ready, words: nil, at: at, typed: .inserted))
        #expect(DiagnosticsReport.text(facts()).contains(" inserted"))
    }
}

/// Canaries: a word and a key that run through real takes and must never
/// reach a log line or the report.
@MainActor @Suite struct DiagnosticsCanaryTests {
    let groq = "https://api.groq.com/openai/v1"
    let canaryWord = "Quokkaberry"
    let canaryKey = "gsk_canarycanary9876"

    @Test func neitherCanaryReachesTheLogOrTheReport() async throws {
        let catalog = try BundledRules.catalog()
        let defaults = try #require(UserDefaults(suiteName: "murmur.tests.\(UUID().uuidString)"))
        let ring = MemoryKeyRing()
        try ring.save(try #require(APIKey(canaryKey)), for: groq)
        var settings = CleanupSettings(polish: false)
        settings.dictionary = [DictionaryEntry(from: "quokka berry", to: canaryWord)]
        settings.expansions = [ExpansionEntry(trigger: "my fruit", text: canaryWord + " jam")]
        CleanupStore(defaults: defaults).save(settings)
        let log = scratchLog()
        let waiting = WaitingStore(directory: FileManager.default.temporaryDirectory.appending(path: "canary-takes-\(UUID().uuidString)", directoryHint: .isDirectory))
        let history = HistoryStore(file: FileManager.default.temporaryDirectory.appending(path: "canary-history-\(UUID().uuidString).jsonl"))
        let mailbox = Mailbox(file: FileManager.default.temporaryDirectory.appending(path: "canary-mailbox-\(UUID().uuidString).json"))
        // The provider hears the word, then refuses the key and says the key
        // back, as some providers do.
        let provider = FakeProvider([
            (200, #"{"text":"quokka berry and my fruit"}"#),
            (401, #"{"error":{"message":"Invalid API Key \#(canaryKey) for \#(canaryWord)"}}"#)
        ])
        let microphone = ScriptedMicrophone(samples: ScriptedMicrophone.tone)
        let model = TakeModel(
            microphone: microphone, store: waiting, rules: try BundledRules.takeRules(), catalog: catalog,
            connections: ConnectionStore(defaults: defaults), cleanup: CleanupStore(defaults: defaults), ring: ring,
            send: provider.send, copy: { _ in },
            record: { try? history.append($0) },
            note: { log.write($0) }
        )
        await model.start()
        await model.stop()
        // The canary really ran through the take.
        #expect(history.list().first?.words.contains(canaryWord) == true)
        await model.start()
        await model.stop()
        #expect(model.waiting.count == 1)
        mailbox.write(MailboxEntry(take: UUID(), phase: .ready, words: canaryWord, at: .now, typed: .offered))
        let report = DiagnosticsReport.text(DiagnosticsReport.facts(
            catalog: catalog, connections: ConnectionStore(defaults: defaults), cleanup: CleanupStore(defaults: defaults), ring: ring,
            log: log, waiting: waiting, history: history, defaults: defaults, keyboard: nil, session: .off, mailbox: mailbox,
            pill: PillLook(style: .bars)
        ))
        let logged = [log.file, log.older].compactMap { try? String(contentsOf: $0, encoding: .utf8) }.joined()
        #expect(logged.contains("take words count=4"))
        #expect(logged.contains("take failed kind=auth status=401 saved=true"))
        #expect(logged.contains(" insert-last"))
        for text in [logged, report] {
            for canary in [canaryWord, canaryKey, "quokka", "canary", "gsk_"] {
                #expect(!text.localizedCaseInsensitiveContains(canary), "\(canary) leaked")
            }
        }
    }
}
