// SPDX-License-Identifier: GPL-3.0-only
// New note (ios/prd.json IOS-023) for the Control Center control, the
// Action Button, and Shortcuts: murmur opens on New note, listening, and
// the words are kept in today's inbox instead of typed. It runs in
// murmur, in front, so the microphone is murmur's as on any take. This
// file is built into the widget extension too, which only shows the
// control; there, NoteControl does nothing and is never reached.
import AppIntents
import Foundation

struct NewNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "New murmur note"
    static let description = IntentDescription("Opens murmur listening for a note. The words are kept in today's inbox instead of typed.")
    static let supportedModes: IntentModes = .foreground

    @MainActor
    func perform() async throws -> some IntentResult {
        NoteControl.open()
        return .result()
    }
}
