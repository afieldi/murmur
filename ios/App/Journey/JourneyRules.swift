// SPDX-License-Identifier: GPL-3.0-only
// The belt ladder and the belts' colors (ios/prd.json IOS-017), from the
// shared data both platforms read: shared/ranks.json and the belt colors in
// shared/cosmetics.json.
import Foundation
import MurmurCore
import SwiftUI

/// The ladder and the belts' colors, read once from the app bundle.
struct JourneyRules: Sendable {
    let ranks: RanksFile
    /// Belt name to its color, from shared/cosmetics.json.
    let beltColors: [String: String]

    /// The app's own, read once.
    static let live: JourneyRules? = try? BundledRules.journey()

    func color(_ belt: String) -> Color {
        (beltColors[belt] ?? beltColors["none"]).map { Color(hex: $0) } ?? Tokens.textDim
    }

    /// A belt's color as fabric on night studio's dark ground, as desktop's
    /// beltOnInk paints it: white as rice paper, the black belt lifted
    /// toward grey so it never vanishes, coral as coral.
    func fabric(_ belt: String) -> Color {
        switch belt {
        case "white": Tokens.rice
        case "black": color("black").mix(with: Tokens.textDim, by: 0.45)
        case let coral where coral.hasPrefix("coral"): color("coral-black")
        default: color(belt)
        }
    }
}

struct BeltColors: Decodable {
    let beltColors: [String: String]
}

private extension Color {
    /// A color from the shared data's #rrggbb; private to this file, so
    /// every other color still comes from the tokens.
    init(hex: String) {
        let digits = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        let red = Double((digits >> 16) & 0xFF) / 255
        let green = Double((digits >> 8) & 0xFF) / 255
        let blue = Double(digits & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }
}
