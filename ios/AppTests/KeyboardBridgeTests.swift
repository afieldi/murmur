// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import MurmurCore
import Testing
@testable import murmur

@MainActor @Suite struct KeyboardBridgeTests {
    let groq = "https://api.groq.com/openai/v1"
    let defaults: UserDefaults
    let ring = MemoryKeyRing()
    let microphone = ScriptedMicrophone(samples: ScriptedMicrophone.tone)
    let mailbox = Mailbox(file: FileManager.default.temporaryDirectory.appending(path: "bridge-\(UUID().uuidString).json"))
    let announced = Announced()

    @MainActor final class Announced {
        var count = 0
    }

    init() throws {
        defaults = try #require(UserDefaults(suiteName: "murmur.tests.\(UUID().uuidString)"))
        try ring.save(try #require(APIKey("gsk_groqgroq1111")), for: groq)
        CleanupStore(defaults: defaults).save(CleanupSettings(polish: false))
    }

    func model(_ provider: FakeProvider) throws -> TakeModel {
        TakeModel(
            microphone: microphone,
            store: WaitingStore(directory: FileManager.default.temporaryDirectory.appending(path: "bridge-takes-\(UUID().uuidString)", directoryHint: .isDirectory)),
            rules: try BundledRules.takeRules(), catalog: try BundledRules.catalog(),
            connections: ConnectionStore(defaults: defaults), cleanup: CleanupStore(defaults: defaults), ring: ring,
            send: provider.send, copy: { _ in }
        )
    }

    func bridge(_ model: TakeModel) -> KeyboardBridge {
        let bridge = KeyboardBridge(model: model, mailbox: mailbox) { [announced] in announced.count += 1 }
        bridge.listen()
        return bridge
    }

    /// Waits for the mailbox to reach a phase, as the keyboard would.
    func waitFor(_ phase: MailboxEntry.Phase) async throws -> MailboxEntry? {
        for _ in 0..<100 {
            if let entry = mailbox.read(), entry.phase == phase { return entry }
            try await Task.sleep(for: .milliseconds(20))
        }
        return mailbox.read()
    }

    @Test func aKeyboardTakeComesBackThroughTheMailbox() async throws {
        let model = try model(.says("Send the invoice tomorrow."))
        let bridge = bridge(model)
        bridge.hear(.start)
        #expect(try await waitFor(.listening) != nil)
        for _ in 0..<100 where !model.isRecording {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(model.isRecording)
        bridge.hear(.stop)
        let ready = try #require(try await waitFor(.ready))
        #expect(ready.words == "Send the invoice tomorrow.")
        #expect(mailbox.claim(ready.take) == "Send the invoice tomorrow.")
        #expect(announced.count >= 2)
    }

    /// A take started on the Dictate screen never goes to the mailbox.
    @Test func aDictateScreenTakeStaysInTheApp() async throws {
        let model = try model(.says("Private words."))
        _ = bridge(model)
        await model.start()
        await model.stop()
        try await Task.sleep(for: .milliseconds(100))
        #expect(mailbox.read() == nil)
    }

    /// The model may still hold the last take's words when the keyboard
    /// starts a new one; those words are never handed over again.
    @Test func aNewTakeNeverCarriesTheLastTakesWords() async throws {
        let model = try model(.says("Old words."))
        await model.start()
        await model.stop()
        let bridge = bridge(model)
        bridge.hear(.start)
        let first = try #require(mailbox.read())
        #expect(first.phase == .listening && first.words == nil)
    }

    @Test func aCancelledTakeEndsAsNothing() async throws {
        let model = try model(.says("never sent"))
        let bridge = bridge(model)
        bridge.hear(.start)
        _ = try await waitFor(.listening)
        try await Task.sleep(for: .milliseconds(50))
        bridge.hear(.cancel)
        #expect(try await waitFor(.nothing) != nil)
        #expect(!model.isRecording)
    }

    @Test func silenceEndsAsNothing() async throws {
        microphone.samples = ScriptedMicrophone.silence
        let model = try model(.says("Thank you."))
        let bridge = bridge(model)
        bridge.hear(.start)
        _ = try await waitFor(.listening)
        try await Task.sleep(for: .milliseconds(50))
        bridge.hear(.stop)
        #expect(try await waitFor(.nothing) != nil)
    }

    @Test func noMicrophoneEndsAsFailed() async throws {
        microphone.allowed = false
        let bridge = bridge(try model(.says("hi")))
        bridge.hear(.start)
        #expect(try await waitFor(.failed) != nil)
    }

    /// A stop with no keyboard take running does nothing.
    @Test func aStrayStopIsIgnored() async throws {
        let model = try model(.says("hi"))
        let bridge = bridge(model)
        bridge.hear(.stop)
        try await Task.sleep(for: .milliseconds(50))
        #expect(mailbox.read() == nil)
        #expect(model.state == .idle)
    }
}
