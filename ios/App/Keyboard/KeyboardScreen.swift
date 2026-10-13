// SPDX-License-Identifier: GPL-3.0-only
// The Keyboard screen (ios/prd.json IOS-008): how to add the murmur
// keyboard and turn on Full Access, why it needs it, a box to try it in,
// and the pill's look (IOS-010). A stand-in until first run (IOS-011)
// walks you through it.
import SwiftUI
import UIKit

struct KeyboardScreen: View {
    @State private var tryIt = ""
    @State private var look = PillLook.read()

    var body: some View {
        Form {
            Section {
                ForEach(Array(KeyboardCopy.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Tokens.brand)
                            .accessibilityHidden(true)
                        Text(step)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Step \(index + 1). \(step)")
                }
                if let settings = URL(string: UIApplication.openSettingsURLString) {
                    Link("Open Settings", destination: settings)
                        .buttonStyle(RowAction())
                }
            } header: {
                SectionTitle("Add the keyboard")
            } footer: {
                Text(KeyboardCopy.fullAccess).foregroundStyle(Tokens.textDim)
            }
            .listRowBackground(Tokens.panel)

            Section {
                HStack(spacing: 12) {
                    ForEach(PillStyle.allCases, id: \.self) { style in
                        LookTile(style: style, chosen: look.style == style) {
                            look = PillLook(style: style)
                            look.write()
                        }
                    }
                }
                .padding(.vertical, 6)
            } header: {
                SectionTitle("The pill")
            } footer: {
                Text(KeyboardCopy.lookFooter).foregroundStyle(Tokens.textDim)
            }
            .listRowBackground(Tokens.panel)

            Section {
                TextField(KeyboardCopy.tryPrompt, text: $tryIt, axis: .vertical)
                    .lineLimit(3...8)
            } header: {
                SectionTitle("Try it here")
            } footer: {
                Text(KeyboardCopy.tryFooter).foregroundStyle(Tokens.textDim)
            }
            .listRowBackground(Tokens.panel)
        }
        .scrollContentBackground(.hidden)
        .background(Tokens.ink)
        .foregroundStyle(Tokens.text)
        .tint(Tokens.brand)
        .navigationTitle("Keyboard")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One look for the pill, live: the style follows a voice, as it will
/// follow yours.
struct LookTile: View {
    let style: PillStyle
    let chosen: Bool
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            VStack(spacing: 8) {
                PillCanvas(style: style, stage: .recording, level: DemoVoice.level)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(height: 44)
                    .background(Capsule().fill(Tokens.panelLift))
                Text(KeyboardCopy.name(style))
                    .font(.subheadline.weight(chosen ? .semibold : .regular))
                    .foregroundStyle(chosen ? Tokens.brand : Tokens.text)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 14).stroke(chosen ? Tokens.brand : Tokens.panelEdge, lineWidth: chosen ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(KeyboardCopy.name(style))
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

/// The Keyboard screen's words.
enum KeyboardCopy {
    static let steps = [
        "Open Settings, then General, then Keyboard, then Keyboards.",
        "Tap Add New Keyboard, and pick murmur.",
        "Tap murmur in the list, and turn on Allow Full Access.",
        "Come back here, tap the box below, and hold the globe key to pick murmur."
    ]

    static let fullAccess = "Full Access lets the keyboard hand your take to the murmur app and read the words back. The keyboard itself never connects to the internet; only the app talks to your provider."

    static let tryPrompt = "Tap here, then the pill"

    static let tryFooter = "Tap the pill, speak, and tap it again. Your words land where the cursor is."

    static let lookFooter = "How the pill looks in the keyboard and when murmur opens to record."

    static func name(_ style: PillStyle) -> String {
        switch style {
        case .bars: "Bars"
        case .speckle: "Speckle"
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack { KeyboardScreen() }.preferredColorScheme(.dark)
}
#endif
