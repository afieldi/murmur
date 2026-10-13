// SPDX-License-Identifier: GPL-3.0-only
// The Journey's paintings (ios/prd.json IOS-018), asked of the painter page
// for where practice stands: the belt, the road, the two gates, and a
// stamp per achievement. Until a picture arrives, or if the page fails,
// the screen keeps its plain native drawing, so the Journey always reads.
import MurmurCore
import Observation
import UIKit

@MainActor @Observable final class JourneyArt {
    /// Desktop's belt is 560 by 120; on iPhone it is set at half that.
    static let beltSize = CGSize(width: 280, height: 60)
    static let wordsHeight: Double = 34
    static let talliesHeight: Double = 44
    static let stampSize: Double = 76
    /// Frames of the tape drop, played over desktop's 520 ms.
    static let tapeFrames = 13
    static let tapeDuration = 0.52

    private(set) var belt: UIImage?
    private(set) var road: JourneyPicture?
    private(set) var words: UIImage?
    private(set) var tallies: UIImage?
    private(set) var stamps: [String: UIImage] = [:]
    /// The newest stripe's tape slapping on, first frame to last.
    private(set) var tape: [UIImage] = []
    /// How many paintings have landed: each one fades in.
    private(set) var painted = 0

    @ObservationIgnored private let painter: JourneyPainter

    init(painter: JourneyPainter = .shared) {
        self.painter = painter
    }

    /// Paints everything for this report. The gates take the row's width.
    func paint(_ report: ProgressReport, rules: JourneyRules, earned: Set<String>, gateWidth: Double, scale: CGFloat) async {
        let standing = Journey.standing(report)
        let size = Self.beltSize
        belt = try? await painter.picture(.belt(belt: report.rank.belt, stripes: report.rank.stripes, width: size.width, height: size.height, drop: nil), scale: scale).image
        road = try? await painter.picture(.road(standing), scale: scale)
        if report.practice.next != nil, gateWidth > 0 {
            words = try? await painter.picture(.words(standing, width: gateWidth, height: Self.wordsHeight), scale: scale).image
            tallies = try? await painter.picture(.tallies(standing, width: gateWidth, height: Self.talliesHeight), scale: scale).image
        }
        painted += 1
        for (index, spec) in rules.achievements.achievements.enumerated() {
            let got = earned.contains(spec.id)
            let artwork = JourneyArtwork.stamp(id: spec.id, got: got, seed: Journey.stampSeed(index), size: Self.stampSize)
            if let image = try? await painter.picture(artwork, scale: scale).image { stamps[spec.id] = image }
        }
        painted += 1
    }

    /// The frames of the newest stripe's tape slapping onto this belt.
    func paintTape(_ rank: RankSpec, scale: CGFloat) async {
        let size = Self.beltSize
        var frames: [UIImage] = []
        for frame in 0..<Self.tapeFrames {
            let k = Double(frame) / Double(Self.tapeFrames - 1)
            guard let image = try? await painter.picture(.belt(belt: rank.belt, stripes: rank.stripes, width: size.width, height: size.height, drop: k), scale: scale).image else { return }
            frames.append(image)
        }
        tape = frames
    }
}
