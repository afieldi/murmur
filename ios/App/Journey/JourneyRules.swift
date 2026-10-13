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
}

struct BeltColors: Decodable {
    let beltColors: [String: String]
}

extension Color {
    /// A color from #rrggbb.
    init(hex: String) {
        let digits = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        let red = Double((digits >> 16) & 0xFF) / 255
        let green = Double((digits >> 8) & 0xFF) / 255
        let blue = Double(digits & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }
}
