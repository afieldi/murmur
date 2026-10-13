// SPDX-License-Identifier: GPL-3.0-only
// Starting and ending a session without opening murmur (ios/prd.json
// IOS-016): the Control Center control, the Action Button, Shortcuts, and
// the Live Activity's End run these. As audio recording and Live Activity
// intents, iOS runs them in murmur's own process even when murmur is not
// open, so the session is the app's one session. This file is built into
// the widget extension too, which only shows the control; there,
// SessionControl does nothing and is never reached.
import AppIntents
import Foundation

struct StartSessionIntent: AudioRecordingIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Start a murmur session"
    static let description = IntentDescription("Keeps the microphone ready so a tap on the murmur keyboard's pill starts a take at once.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        switch await SessionControl.start() {
        case .started:
            return .result(dialog: IntentDialog(stringLiteral: SessionIntentCopy.started))
        case .noMicrophone:
            return .result(dialog: IntentDialog(stringLiteral: SessionIntentCopy.noMicrophone))
        case .unavailable:
            return .result(dialog: IntentDialog(stringLiteral: SessionIntentCopy.unavailable))
        }
    }
}

struct EndSessionIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "End the murmur session"
    static let description = IntentDescription("Lets the microphone go.")

    func perform() async throws -> some IntentResult {
        await SessionControl.end()
        return .result()
    }
}

/// How a start went.
enum SessionStart: Sendable, Equatable {
    case started
    /// murmur may not use the microphone yet; it can only be allowed in murmur.
    case noMicrophone
    /// murmur's own files could not be read.
    case unavailable
}

/// What the intents say.
enum SessionIntentCopy {
    static let started = "murmur is listening for your next take."
    static let noMicrophone = "Open murmur once to allow the microphone, then try again."
    static let unavailable = "murmur could not start. Open murmur and try again."
}
