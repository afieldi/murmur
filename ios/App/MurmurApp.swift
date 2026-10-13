// SPDX-License-Identifier: GPL-3.0-only
// murmur for iPhone. The app holds the microphone, the key, the cleanup,
// and the history; the keyboard extension stays thin (ios/prd.json).
import SwiftUI

@main
struct MurmurApp: App {
    init() {
        if let request = SmokeRequest(arguments: ProcessInfo.processInfo.arguments) {
            SmokeRunner.runAndExit(request)
        }
        if ProcessInfo.processInfo.arguments.contains("--pill-shots") {
            PillShots.runAndExit()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
