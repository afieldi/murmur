// SPDX-License-Identifier: GPL-3.0-only
// The session's Live Activity (ios/prd.json IOS-016): what the Lock Screen
// and the Dynamic Island show while a session runs. iOS redraws it only now
// and then, so it holds still states: Ready or Recording, and when the
// session ends. It never follows the voice.
import ActivityKit
import Foundation

struct SessionActivity: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        /// A take is recording now.
        var recording: Bool
        /// When the session ends unless another take comes first.
        var until: Date
    }
}

/// What the Live Activity says, kept here so the app's tests can read it.
enum SessionActivityCopy {
    static let ready = "Ready"
    static let recording = "Recording"
    static let end = "End"
    static let title = "murmur"

    static func state(_ recording: Bool) -> String {
        recording ? self.recording : ready
    }
}
