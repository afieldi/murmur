// SPDX-License-Identifier: GPL-3.0-only
// The promotion ceremony (ios/prd.json IOS-018), as desktop holds it: one
// big stroke in the new belt's color, splatter, and the rank set large.
// The painting runs in the painter page on screen; the rank, its title,
// and what earned it are native text over it. A tap, or VoiceOver's
// escape, continues; without VoiceOver it also closes on its own after
// desktop's 4.6 seconds. Reduce Motion shows the finished painting at once.
import MurmurCore
import SwiftUI
import WebKit

/// The page's web view, as a view.
private struct Stage: UIViewRepresentable {
    let painter: JourneyPainter

    func makeUIView(context: Context) -> WKWebView { painter.web }
    func updateUIView(_ view: WKWebView, context: Context) {}
}

struct CeremonyView: View {
    static let duration = 4.6
    static let textDelay = 0.48

    let rank: RankSpec
    let close: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var painter: JourneyPainter?
    @State private var painted = false
    @State private var shown = false
    @ScaledMetric(relativeTo: .largeTitle) private var rankSize = 48

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                if let painter {
                    Stage(painter: painter)
                        .ignoresSafeArea()
                        .accessibilityHidden(true)
                }
                VStack(spacing: 14) {
                    Text(rank.label)
                        .font(.system(size: rankSize, weight: .heavy).width(.condensed))
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.6)
                    Text("\u{201C}\(rank.title)\u{201D}")
                        .font(.title3.italic())
                        .foregroundStyle(Tokens.textDim)
                    if let earned = JourneyCopy.earnedWith(rank) {
                        Text(earned)
                            .font(.system(.footnote, design: .monospaced))
                    }
                    Text(JourneyCopy.continueHint)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Tokens.textDim)
                        .padding(.top, 14)
                }
                .padding(.horizontal, 16)
                .padding(.top, geometry.size.height * 0.54)
                .opacity(shown ? 1 : 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(Tokens.text)
            .contentShape(Rectangle())
            .onTapGesture(perform: close)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.escape, close)
            .accessibilityAction(named: JourneyCopy.continueHint, close)
            .task(id: geometry.size) {
                await paint(geometry.size)
            }
        }
        .background(Tokens.ink.opacity(0.95))
        .task {
            if reduceMotion {
                shown = true
            } else {
                try? await Task.sleep(for: .seconds(Self.textDelay))
                withAnimation(.easeOut(duration: 0.4)) { shown = true }
            }
            guard !voiceOver else { return }
            try? await Task.sleep(for: .seconds(Self.duration - (reduceMotion ? 0 : Self.textDelay)))
            close()
        }
    }

    /// Paints once the size is known: the stroke goes on the first time,
    /// and a new size repaints the finished picture, as desktop does.
    private func paint(_ size: CGSize) async {
        guard size.width > 0, size.height > 0 else { return }
        let painter = painter ?? JourneyPainter()
        self.painter = painter
        let finished = reduceMotion || painted
        painted = true
        try? await painter.ceremony(rank: rank.id, size: size, reduced: finished)
    }
}
