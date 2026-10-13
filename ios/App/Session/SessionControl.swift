// SPDX-License-Identifier: GPL-3.0-only
// The app's side of the session intents (ios/prd.json IOS-016). iOS runs
// them in murmur's process, maybe with no screen open, so starting brings
// up what the first screen would: the keyboard's bridge and the one
// session.
import Foundation

@MainActor enum SessionControl {
    /// The session the intents start and end: the app's one session, with
    /// the keyboard's bridge listening, as the first screen would bring up.
    /// The smoke and the tests give their own.
    static var source: @MainActor () -> Session? = {
        _ = KeyboardBridge.live()
        return Session.live()
    }

    /// Starts the session, or counts its length again from now.
    static func start() async -> SessionStart {
        guard let session = source() else { return .unavailable }
        return await session.begin() ? .started : .noMicrophone
    }

    /// Ends the session. From a Live Activity left over after murmur
    /// closed, bringing the session up ends that activity too.
    static func end() async {
        source()?.end()
    }
}
