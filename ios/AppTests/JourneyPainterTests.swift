// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Testing
import UIKit
import WebKit
@testable import murmur

/// How two paintings differ, pixel by pixel: the share of color bytes that
/// differ and the largest difference. A canvas on the GPU can round a
/// blend by one level from run to run, which nobody can see.
struct PaintingDifference {
    let share: Double
    let largest: Int

    /// The same painting, give or take the GPU's rounding.
    var same: Bool { largest <= 2 && share < 0.005 }

    init(_ a: UIImage, _ b: UIImage) {
        let left = Self.bytes(a)
        let right = Self.bytes(b)
        guard left.count == right.count, !left.isEmpty else {
            share = 1
            largest = 255
            return
        }
        var differing = 0
        var largest = 0
        for index in left.indices where left[index] != right[index] {
            differing += 1
            largest = max(largest, abs(Int(left[index]) - Int(right[index])))
        }
        share = Double(differing) / Double(left.count)
        self.largest = largest
    }

    static func bytes(_ image: UIImage) -> [UInt8] {
        guard let cg = image.cgImage else { return [] }
        var bytes = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: cg.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            return true
        }
        return drawn ? bytes : []
    }
}

/// The Journey's painter page in its web view (IOS-018).
@MainActor @Suite(.serialized) struct JourneyPainterTests {
    let standing = JourneyStanding(rank: "white-2", next: "white-3", words: 7380, days: 7)

    @Test func thePageIsInTheAppAndSaysReady() async throws {
        let url = try #require(JourneyPage.url)
        #expect(try String(contentsOf: url, encoding: .utf8).contains("murmurJourney"))
        try await JourneyPainter().waitUntilReady()
    }

    /// A page that never says ready fails in time, so the Journey keeps its
    /// plain drawing.
    @Test func aMissingPageFailsInTime() async {
        await #expect(throws: JourneyPainter.Failure.notReady) {
            try await JourneyPainter(page: nil).waitUntilReady(seconds: 0.3)
        }
    }

    /// A picture comes back as an image of the size asked for, at the
    /// screen's scale, and the same request paints the same picture.
    @Test func aBeltIsPaintedAtItsSize() async throws {
        let painter = JourneyPainter()
        let request = JourneyArtwork.belt(belt: "blue", stripes: 2, width: 168, height: 40, drop: nil)
        let belt = try await painter.picture(request, scale: 2)
        #expect(belt.image.size == CGSize(width: 168, height: 40))
        #expect(belt.image.scale == 2)
        let again = try await painter.picture(request, scale: 2)
        #expect(PaintingDifference(again.image, belt.image).same)
    }

    /// Mid drop the newest tape is still in the air: the frame differs from
    /// the finished belt, and the last frame is the finished belt.
    @Test func theTapeDropsOntoTheBelt() async throws {
        let painter = JourneyPainter()
        let finished = try await painter.picture(.belt(belt: "white", stripes: 3, width: 140, height: 30, drop: nil), scale: 2)
        let middle = try await painter.picture(.belt(belt: "white", stripes: 3, width: 140, height: 30, drop: 0.3), scale: 2)
        let landed = try await painter.picture(.belt(belt: "white", stripes: 3, width: 140, height: 30, drop: 1), scale: 2)
        #expect(!PaintingDifference(middle.image, finished.image).same)
        #expect(PaintingDifference(landed.image, finished.image).same)
    }

    /// The road comes back without its words, and with where to set them.
    @Test func theRoadComesWithItsWords() async throws {
        let road = try await JourneyPainter().picture(.road(standing), scale: 2)
        #expect(road.image.size == CGSize(width: 1500, height: 120))
        #expect(road.groups.map(\.name).prefix(3) == ["white", "blue", "purple"])
        #expect(road.groups.map(\.name).contains("coral"))
        let you = try #require(road.you)
        #expect(you > 34 && you < 1500)
    }

    @Test func gatesAndStampsArePainted() async throws {
        let painter = JourneyPainter()
        for request in [
            JourneyArtwork.words(standing, width: 320, height: 34),
            .tallies(standing, width: 320, height: 44),
            .stamp(id: "streak-7", got: true, seed: 1209, size: 76),
            .stamp(id: "marathon", got: false, seed: 1290, size: 76)
        ] {
            let picture = try await painter.picture(request, scale: 3)
            #expect(picture.image.size.width > 0)
        }
    }

    /// The ceremony paints on the page's own canvases; an unknown rank
    /// paints nothing.
    @Test func theCeremonyPaints() async throws {
        let painter = JourneyPainter()
        try await painter.ceremony(rank: "blue", size: CGSize(width: 390, height: 844), reduced: true)
        await #expect(throws: JourneyPainter.Failure.badPicture) {
            try await painter.ceremony(rank: "gold-9", size: CGSize(width: 390, height: 844), reduced: true)
        }
    }

    /// The page can fetch nothing: its content policy refuses it, even a
    /// file beside it in the bundle.
    @Test func thePageCanFetchNothing() async throws {
        let painter = JourneyPainter()
        try await painter.waitUntilReady()
        for target in ["https://example.com", "journey.html"] {
            let answer = try await painter.web.callAsyncJavaScript(
                "try { await fetch(target); return 'fetched' } catch { return 'refused' }", arguments: ["target": target], contentWorld: .page
            )
            #expect(answer as? String == "refused")
        }
    }

    /// The page cannot go anywhere: after its own file loads, every
    /// navigation is refused, and the painter keeps working.
    @Test func thePageCannotNavigate() async throws {
        let painter = JourneyPainter()
        try await painter.waitUntilReady()
        let page = painter.web.url
        for target in ["https://example.com", "journey.html"] {
            _ = try? await painter.web.evaluateJavaScript("location.href = '\(target)'; 1")
            try await Task.sleep(for: .milliseconds(400))
            #expect(painter.web.url == page)
        }
        let kind = try await painter.web.evaluateJavaScript("typeof window.murmurJourney")
        #expect(kind as? String == "object")
    }

    /// The page is one file in the bundle's web folder.
    @Test func thePageIsOneFileInTheBundle() throws {
        let page = try #require(JourneyPage.url)
        #expect(page.isFileURL)
        #expect(page.path().hasPrefix(Bundle.main.bundlePath))
        #expect(page.deletingLastPathComponent().lastPathComponent == "web")
    }
}
