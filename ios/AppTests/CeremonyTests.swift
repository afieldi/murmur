// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import MurmurCore
import SwiftUI
import Testing
import UIKit
@testable import murmur

/// When the ceremony closed, from its close button or its own clock.
@MainActor final class ClosedAt {
    var at: Date?
}

/// The promotion ceremony (IOS-018).
@MainActor @Suite(.serialized) struct CeremonyTests {
    /// The ceremony's clock starts when its painting does, so a page slow to
    /// start never cuts the stroke short.
    @Test func theClockStartsWithThePainting() async throws {
        // A page that says it is ready only after 1.2 seconds.
        let url = FileManager.default.temporaryDirectory.appending(path: "journey-slow-\(UUID().uuidString).html")
        try """
        <!doctype html><script>
        window.murmurJourney = { ceremony: () => true }
        setTimeout(() => window.webkit.messageHandlers.journey.postMessage({ type: 'ready' }), 1200)
        </script>
        """.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        let blue = try #require(BundledRules.journey().ranks.ranks.first { $0.id == "blue" })
        let closed = ClosedAt()
        let painter = JourneyPainter(page: url)
        let host = UIHostingController(rootView: CeremonyView(rank: blue, painter: painter, duration: 0.5) { closed.at = .now })
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        try await painter.waitUntilReady(seconds: 10)
        let ready = Date.now
        for _ in 0..<50 where closed.at == nil {
            try await Task.sleep(for: .seconds(0.1))
        }
        let at = try #require(closed.at, "it never closed")
        #expect(at.timeIntervalSince(ready) >= 0.4, "it closed \(at.timeIntervalSince(ready)) seconds after its painting started")
    }
}
