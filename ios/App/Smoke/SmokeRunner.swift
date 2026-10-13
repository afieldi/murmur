// SPDX-License-Identifier: GPL-3.0-only
// The headless smoke (npm run ios:smoke): launched with --smoke, the app
// runs every subsystem check, prints one SMOKE_RESULT line, and exits.
// The same contract as desktop's smoke: {"ok": Bool, "checks": {name: Bool}},
// and a failed check explains itself on a line starting "smoke <name>:".
import Foundation
import MurmurCore
import Synchronization

struct SmokeRequest: Equatable {
    /// How many shared rule files the build bundled; -1 when not given,
    /// which no real count matches.
    let sharedCount: Int

    /// Nil unless the app was launched with --smoke.
    init?(arguments: [String]) {
        guard arguments.contains("--smoke") else { return nil }
        let prefix = "--shared-count="
        sharedCount = arguments.lazy
            .filter { $0.hasPrefix(prefix) }
            .compactMap { Int($0.dropFirst(prefix.count)) }
            .first ?? -1
    }
}

struct SmokeFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

enum SmokeRunner {
    static func runAndExit(_ request: SmokeRequest) -> Never {
        let checks: [(name: String, run: () throws -> Void)] = [
            ("appGroup", checkAppGroup),
            ("keychain", checkKeychain),
            ("keyRing", checkKeyRing),
            ("connectionTest", checkConnectionTest),
            ("speechGate", checkSpeechGate),
            ("transcription", checkTranscription),
            ("waitingTakes", checkWaitingTakes),
            ("polish", checkPolish),
            ("mailbox", checkMailbox),
            ("session", checkSession),
            ("pill", checkPill),
            ("firstRun", checkFirstRun),
            ("history", checkHistory),
            ("sharedJson", { try checkSharedJson(expected: request.sharedCount) })
        ]
        var results: [String: Bool] = [:]
        for check in checks {
            do {
                try check.run()
                results[check.name] = true
            } catch {
                results[check.name] = false
                emit("smoke \(check.name): \(error)")
            }
        }
        let ok = results.values.allSatisfy { $0 }
        let payload: [String: Any] = ["ok": ok, "checks": results]
        let json = (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])) ?? Data()
        emit("SMOKE_RESULT " + String(decoding: json, as: UTF8.self))
        exit(ok ? 0 : 1)
    }

    /// Unbuffered, so nothing is lost when the app exits right after.
    private static func emit(_ line: String) {
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }

    static func checkAppGroup() throws {
        guard let container = AppGroup.containerURL else {
            throw SmokeFailure("no container for \(AppGroup.identifier)")
        }
        let probe = container.appendingPathComponent("smoke-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: probe) }
        try Data("murmur smoke".utf8).write(to: probe)
        let back = try String(contentsOf: probe, encoding: .utf8)
        guard back == "murmur smoke" else { throw SmokeFailure("read back \(back)") }
    }

    static func checkKeychain() throws {
        let store = KeychainStore(service: "com.lbwalton.murmur.ios.smoke")
        let account = "smoke"
        defer { try? store.delete(account: account) }
        try store.save("not-a-real-key", account: account)
        guard try store.read(account: account) == "not-a-real-key" else {
            throw SmokeFailure("read back a different value")
        }
        try store.delete(account: account)
        guard try store.read(account: account) == nil else {
            throw SmokeFailure("delete left the item behind")
        }
    }

    /// A dummy key through the key ring: saved, read back, filed in the
    /// app's own Keychain access group (never the app group, which the
    /// keyboard can read), kept out of the app's defaults, and deleted.
    static func checkKeyRing() throws {
        let ring = KeychainKeyRing()
        let url = "https://smoke.invalid/v1/"
        defer { try? ring.remove(for: url) }
        guard let key = APIKey(StubProtocol.key) else { throw SmokeFailure("the dummy key did not parse") }
        try ring.save(key, for: url)
        guard try ring.key(for: "https://smoke.invalid/v1") == key else {
            throw SmokeFailure("read back a different key")
        }
        let group = try ring.store.accessGroup(account: BaseURL.normalized(url)) ?? ""
        guard group != AppGroup.identifier, group.hasSuffix("." + (Bundle.main.bundleIdentifier ?? "?")) else {
            throw SmokeFailure("the key sits in access group \(group)")
        }
        guard !"\(UserDefaults.standard.dictionaryRepresentation())".contains(key.secret) else {
            throw SmokeFailure("the key reached the app's defaults")
        }
        try ring.remove(for: url)
        guard try ring.key(for: url) == nil else { throw SmokeFailure("remove left the key behind") }
    }

    /// Test connection against the local stand-in, once for each answer.
    static func checkConnectionTest() throws {
        guard let key = APIKey(StubProtocol.key) else { throw SmokeFailure("the dummy key did not parse") }
        let session = StubProtocol.session()
        for answer in StubProtocol.Answer.allCases {
            let verdict = waitFor { await ConnectionTest.run(baseUrl: answer.baseUrl, key: key, send: { try await session.data(for: $0) }) }
            guard verdict == answer.expected else {
                throw SmokeFailure("\(answer.rawValue) gave \(verdict), expected \(answer.expected)")
            }
        }
    }

    /// A generated tone passes the speech gate and a generated silence
    /// does not; a phrase models invent on silence is heard as nothing.
    static func checkSpeechGate() throws {
        let rules = try BundledRules.takeRules()
        guard TakeAudio.upload(ScriptedMicrophone.tone, gate: rules.gate) != nil else {
            throw SmokeFailure("the tone did not pass the gate")
        }
        guard TakeAudio.upload(ScriptedMicrophone.silence, gate: rules.gate) == nil else {
            throw SmokeFailure("silence passed the gate")
        }
        guard TakeAudio.heard("Thank you.", list: rules.hallucinations) == nil,
              TakeAudio.heard("Send the invoice tomorrow.", list: rules.hallucinations) != nil
        else { throw SmokeFailure("the hallucination filter misjudged a transcript") }
    }

    /// A take, gated and encoded, goes to the local stand-in through the
    /// real URLSession, and its words come back.
    static func checkTranscription() throws {
        guard let key = APIKey(StubProtocol.key) else { throw SmokeFailure("the dummy key did not parse") }
        let rules = try BundledRules.takeRules()
        guard let wav = TakeAudio.upload(ScriptedMicrophone.tone, gate: rules.gate) else { throw SmokeFailure("the tone did not pass the gate") }
        let session = StubProtocol.session()
        let result = waitFor { await Transcription.run(wav: wav, baseUrl: StubProtocol.wordsBaseUrl, model: "smoke-model", key: key, send: { try await session.data(for: $0) }) }
        guard case .words(let text) = result, TakeAudio.heard(text, list: rules.hallucinations) == StubProtocol.words else {
            throw SmokeFailure("the stand-in gave \(result)")
        }
    }

    /// A take that fails waits in a scratch folder with protection that
    /// allows writing after first unlock, then a retry delivers it and its
    /// audio goes.
    static func checkWaitingTakes() throws {
        guard let key = APIKey(StubProtocol.key) else { throw SmokeFailure("the dummy key did not parse") }
        let store = WaitingStore(directory: FileManager.default.temporaryDirectory.appending(path: "smoke-waiting-\(UUID().uuidString)", directoryHint: .isDirectory))
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let rules = try BundledRules.takeRules()
        guard let wav = TakeAudio.upload(ScriptedMicrophone.tone, gate: rules.gate) else { throw SmokeFailure("the tone did not pass the gate") }
        let session = StubProtocol.session()
        let down = waitFor { await Transcription.run(wav: wav, baseUrl: StubProtocol.downBaseUrl, model: "smoke-model", key: key, send: { try await session.data(for: $0) }) }
        guard case .failed(let kind, let detail) = down, kind == .server else { throw SmokeFailure("the down host gave \(down)") }
        let id = try store.save(wav, startedAt: .now, failure: TakeFailure(kind: kind.rawValue, detail: detail))
        guard store.list().map(\.id) == [id], store.take(id)?.failure?.kind == "server" else { throw SmokeFailure("the failed take did not list") }
        let protection = try store.directory.appending(path: "\(id).wav").resourceValues(forKeys: [.fileProtectionKey]).fileProtection
        guard protection == .completeUntilFirstUserAuthentication else { throw SmokeFailure("the audio has protection \(String(describing: protection))") }
        let audio = try store.audio(id)
        let retried = waitFor { await Transcription.run(wav: audio, baseUrl: StubProtocol.wordsBaseUrl, model: "smoke-model", key: key, send: { try await session.data(for: $0) }) }
        guard retried == .words(StubProtocol.words) else { throw SmokeFailure("the retry gave \(retried)") }
        try store.remove(id)
        guard store.list().isEmpty else { throw SmokeFailure("the delivered take is still waiting") }
    }

    /// Polish pointed at a stand-in that errors, then at one that chats:
    /// both give back the formatted text unchanged, and say why.
    static func checkPolish() throws {
        guard let key = APIKey(StubProtocol.key) else { throw SmokeFailure("the dummy key did not parse") }
        let rules = try BundledRules.takeRules()
        let heard = "um send the report tomorrow and copy the whole team on it please"
        let formatted = formatTranscript(heard, options: FormatOptions(), spec: rules.format)
        let session = StubProtocol.session()
        for baseUrl in [StubProtocol.chatErrorBaseUrl, StubProtocol.chattyBaseUrl] {
            let connection = PolishConnection(baseUrl: baseUrl, model: "smoke-model", key: key)
            let reasons = Reasons()
            let text = waitFor {
                await Cleanup.finish(heard, settings: CleanupSettings(), rules: rules.cleanup, connection: connection, send: { try await session.data(for: $0) }) { reason in
                    reasons.list.withLock { $0.append(reason) }
                }
            }
            guard text == formatted else { throw SmokeFailure("\(baseUrl) changed the text to \(text)") }
            guard reasons.list.withLock({ $0.count }) == 1 else { throw SmokeFailure("polish at \(baseUrl) did not fall back") }
        }
    }

    /// A mailbox round trip in the app group: the app posts a take, a
    /// simulated keyboard reads it once, and a second read gets nothing.
    static func checkMailbox() throws {
        guard let container = AppGroup.containerURL else { throw SmokeFailure("no container for \(AppGroup.identifier)") }
        let mailbox = Mailbox(file: container.appending(path: "smoke-mailbox-\(UUID().uuidString).json"))
        defer { try? FileManager.default.removeItem(at: mailbox.file) }
        let take = UUID()
        mailbox.write(MailboxEntry(take: take, phase: .ready, words: "smoke words for the keyboard", at: .now))
        guard mailbox.claim(take) == "smoke words for the keyboard" else { throw SmokeFailure("the keyboard did not get the words") }
        guard mailbox.claim(take) == nil, mailbox.claim() == nil else { throw SmokeFailure("a second read got the words again") }
    }

    /// A session at a shortened length, through the device microphone's own
    /// gate with sound handed in instead of heard: it starts warm, a take
    /// holds only what was said during it (a steady sound before and after
    /// never reaches it), and with no further take the session ends by
    /// itself and lets the microphone go. No audio file exists anywhere
    /// from between takes.
    static func checkSession() throws {
        if let failure = onMain({ await sessionFailure() }) { throw SmokeFailure(failure) }
    }

    @MainActor private static func sessionFailure() async -> String? {
        guard let microphone = FedMicrophone(rate: Double(Wav.targetSampleRate)), let key = APIKey(StubProtocol.key),
              let defaults = UserDefaults(suiteName: "murmur.smoke.\(UUID().uuidString)"),
              let catalog = try? BundledRules.catalog(), let rules = try? BundledRules.takeRules()
        else { return "the stand-ins did not build" }
        let scratch = FileManager.default.temporaryDirectory.appending(path: "smoke-session-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let connections = ConnectionStore(defaults: defaults)
        let ring = MemoryKeyRing()
        try? ring.save(key, for: connections.load(catalog: catalog).transcription.baseUrl)
        let cleanup = CleanupStore(defaults: defaults)
        cleanup.save(CleanupSettings(polish: false))
        let model = TakeModel(
            microphone: microphone, store: WaitingStore(directory: scratch.appending(path: "takes", directoryHint: .isDirectory)),
            rules: rules, catalog: catalog, connections: connections, cleanup: cleanup, ring: ring,
            send: { request in (Data(#"{"text":"smoke session words"}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!) },
            copy: { _ in }
        )
        let file = scratch.appending(path: "session.json")
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let session = Session(microphone: microphone, model: model, defaults: defaults, stateFile: file, seconds: { _ in 0.5 }, announce: { _ in })
        session.listen()
        guard await session.begin(), microphone.isWarm, SessionState.read(from: file).isOn() else { return "the session did not start warm" }
        let steady = [Float](repeating: 0.5, count: Wav.targetSampleRate / 2)
        microphone.hear(steady)
        await model.start()
        microphone.hear(ScriptedMicrophone.tone)
        await model.stop()
        microphone.hear(steady)
        guard case .words = model.state else { return "the take gave \(model.state)" }
        let take = microphone.lastTake
        guard abs(take.count - ScriptedMicrophone.tone.count) < 200, take.allSatisfy({ abs($0) < 0.35 }) else {
            return "the take held \(take.count) samples, peak \(take.map(abs).max() ?? 0)"
        }
        guard session.isOn, microphone.isWarm else { return "the session let go after a take" }
        for _ in 0..<150 where session.isOn {
            try? await Task.sleep(for: .milliseconds(20))
        }
        guard !session.isOn, !microphone.isWarm, SessionState.read(from: file) == .off else { return "the session did not end by itself" }
        var places = [scratch]
        if let container = AppGroup.containerURL { places.append(container) }
        for place in places {
            let audio = (FileManager.default.subpaths(atPath: place.path) ?? []).filter { $0.hasSuffix(".wav") }
            guard audio.isEmpty else { return "audio exists in \(place.lastPathComponent): \(audio)" }
        }
        return nil
    }

    /// The pill draws every stage of both styles (IOS-010), and the level
    /// file the keyboard reads round trips in the app group.
    static func checkPill() throws {
        guard let container = AppGroup.containerURL else { throw SmokeFailure("no container for \(AppGroup.identifier)") }
        let levels = LevelFile(url: container.appending(path: "smoke-level-\(UUID().uuidString)"))
        defer { levels.url.map { try? FileManager.default.removeItem(at: $0) } }
        levels.write(0.5, count: 3)
        guard let read = levels.read(), read.level == 0.5, read.count == 3 else { throw SmokeFailure("the level file read back \(String(describing: levels.read()))") }
        let blank = PillShots.shots.filter { (PillShots.image($0.frame).pngData()?.count ?? 0) < 1_000 }.map(\.name)
        guard blank.isEmpty else { throw SmokeFailure("these stages drew nothing: \(blank)") }
    }

    /// First run walks its steps with each permission granted and refused
    /// (IOS-011): the microphone allowed or not, and Full Access on (the
    /// keyboard reports itself) or off (it cannot, so your word adds the
    /// keyboard). Whatever was refused says so and waits on Home while the
    /// rest go on.
    static func checkFirstRun() throws {
        if let failure = onMain({ await firstRunFailure() }) { throw SmokeFailure(failure) }
    }

    @MainActor private static func firstRunFailure() async -> String? {
        for allowed in [true, false] {
            for fullAccess in [true, false] {
                guard let defaults = UserDefaults(suiteName: "murmur.smoke.\(UUID().uuidString)") else { return "no scratch defaults" }
                let report = Cell<KeyboardReport?>(nil)
                let key = Cell(false)
                let setup = Setup(microphone: ScriptedAccess(answer: allowed), report: { report.value }, hasKey: { key.value }, defaults: defaults)
                let walk = "microphone \(allowed ? "allowed" : "refused"), Full Access \(fullAccess ? "on" : "off")"
                guard setup.next == .microphone else { return "\(walk): first run did not start with the microphone" }
                await setup.allowMicrophone()
                guard setup.status(.microphone) == (allowed ? .done : .denied) else { return "\(walk): the microphone read \(setup.status(.microphone))" }
                if fullAccess {
                    report.value = KeyboardReport(fullAccess: true, at: .now)
                    setup.refresh()
                    guard setup.status(.keyboard) == .done, setup.status(.fullAccess) == .done else { return "\(walk): the report did not prove both keyboard steps" }
                } else {
                    setup.keyboardAdded()
                    guard setup.status(.keyboard) == .done, setup.status(.fullAccess) == .todo else { return "\(walk): the keyboard steps read wrong without a report" }
                }
                key.value = true
                setup.refresh()
                setup.practiced()
                let left = (allowed ? [] : [Setup.Step.microphone]) + (fullAccess ? [] : [Setup.Step.fullAccess])
                guard setup.remaining == left else { return "\(walk): left \(setup.remaining)" }
            }
        }
        return nil
    }

    /// History in a scratch folder (IOS-012): three takes written read back
    /// newest first, one deletes, Clear all empties it, and the folder is
    /// out of backups with the file writable after first unlock.
    static func checkHistory() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "smoke-history-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = HistoryStore(file: folder.appending(path: "history.jsonl"))
        let takes = ["The first smoke take.", "The second smoke take.", "The third smoke take."].enumerated().map { index, words in
            HistoryEntry(at: Date(timeIntervalSince1970: 1_790_000_000 + Double(index) * 60), durationMs: 1_500, words: words)
        }
        for take in takes { try store.append(take) }
        guard store.list() == takes.reversed() else { throw SmokeFailure("history read back \(store.list().map(\.words))") }
        try store.remove(takes[1].id)
        guard store.list() == [takes[2], takes[0]] else { throw SmokeFailure("deleting one left \(store.list().map(\.words))") }
        guard try folder.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true else { throw SmokeFailure("history is in backups") }
        let protection = try store.file.resourceValues(forKeys: [.fileProtectionKey]).fileProtection
        guard protection == .completeUntilFirstUserAuthentication else { throw SmokeFailure("history has protection \(String(describing: protection))") }
        try store.clear()
        guard store.list().isEmpty else { throw SmokeFailure("Clear all left takes") }
    }

    /// Runs main-actor work to the end from the smoke's synchronous start
    /// on the main thread, turning the run loop so the work gets to run.
    private static func onMain<T: Sendable>(_ work: @escaping @MainActor () async -> T) -> T {
        let outcome = Mutex<(done: Bool, value: T?)>((false, nil))
        Task { @MainActor in
            let value = await work()
            outcome.withLock { $0 = (true, value) }
        }
        while !outcome.withLock({ $0.done }) {
            RunLoop.main.run(mode: .default, before: .now.addingTimeInterval(0.01))
        }
        guard let value = outcome.withLock({ $0.value }) else { preconditionFailure("the work finished without a value") }
        return value
    }

    /// Fallback reasons, collected across the smoke's async bridge.
    private final class Reasons: Sendable {
        let list = Mutex<[String]>([])
    }

    /// Runs async work to the end from the smoke's synchronous start.
    private static func waitFor<T: Sendable>(_ work: @escaping @Sendable () async -> T) -> T {
        let result = Mutex<T?>(nil)
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            let value = await work()
            result.withLock { $0 = value }
            done.signal()
        }
        done.wait()
        guard let value = result.withLock({ $0 }) else { preconditionFailure("the work signaled without a value") }
        return value
    }

    static func checkSharedJson(expected: Int) throws {
        guard let directory = Bundle.main.url(forResource: "shared", withExtension: nil) else {
            throw SmokeFailure("no shared folder in the app bundle")
        }
        let names = try SharedData(directory: directory).validateAll()
        guard names.count == expected else {
            throw SmokeFailure("bundled \(names.count) shared rules, expected \(expected)")
        }
    }
}
