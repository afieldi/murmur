// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Testing
@testable import murmur

/// Starting and ending a session without opening murmur (IOS-016): the
/// intents Control Center, the Action Button, Shortcuts, and the Live
/// Activity's End run.
@MainActor @Suite(.serialized) struct SessionControlTests {
    let microphone = ScriptedMicrophone(samples: ScriptedMicrophone.tone)
    let shown = ShownStates()

    /// The intents start and end the session they are given, and say when
    /// the microphone is not allowed yet.
    @Test func theIntentsStartAndEndTheSession() async throws {
        let (session, _) = try scriptedSession(microphone, shown: shown)
        let before = SessionControl.source
        defer { SessionControl.source = before }
        SessionControl.source = { session }
        _ = try await StartSessionIntent().perform()
        #expect(session.isOn)
        #expect(microphone.isWarm)
        _ = try await EndSessionIntent().perform()
        #expect(!session.isOn)
        #expect(!microphone.isWarm)
        microphone.allowed = false
        #expect(await SessionControl.start() == .noMicrophone)
        #expect(!session.isOn)
        SessionControl.source = { nil }
        #expect(await SessionControl.start() == .unavailable)
    }

    @Test func whatTheIntentsSayFollowsTheWritingRules() {
        for line in [SessionIntentCopy.started, SessionIntentCopy.noMicrophone, SessionIntentCopy.unavailable] {
            #expect(!line.contains("Murmur"))
            #expect(!line.contains("\u{2014}") && !line.contains(" - ") && !line.contains("--"))
        }
    }
}
