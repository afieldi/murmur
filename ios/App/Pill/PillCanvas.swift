// SPDX-License-Identifier: GPL-3.0-only
// The pill on the app's screens (ios/prd.json IOS-010): the same PillView
// the keyboard draws, so every place shows one pill.
import SwiftUI

struct PillCanvas: UIViewRepresentable {
    var style: PillStyle
    var stage: PillStage
    /// Reads how loud the take is now, while recording.
    var level: (@MainActor () -> Float)?

    func makeUIView(context: Context) -> PillView {
        PillView()
    }

    func updateUIView(_ view: PillView, context: Context) {
        view.style = style
        view.level = level
        view.show(stage)
    }
}

extension PillStage {
    /// The pill's stage for a take in the app.
    init(_ state: TakeModel.State) {
        switch state {
        case .idle: self = .idle
        case .recording: self = .recording
        case .transcribing: self = .processing
        case .words: self = .inserted
        case .heardNothing: self = .noSpeech
        case .failed, .micOff, .micFailed: self = .error
        }
    }
}

/// A voice for the pill where there is none to hear: the Look tiles, the
/// previews, and the capture script.
enum DemoVoice {
    // Each step is its own typed value: Swift 6.3 (CI) gives up type
    // checking these as one expression.
    @MainActor static func level() -> Float {
        let t: Double = CACurrentMediaTime()
        let swing: Double = abs(sin(t * 3.7))
        let shape: Double = 0.55 + 0.45 * sin(t * 1.1)
        return Float(0.08 + 0.82 * swing * shape)
    }

    /// A take's worth of levels, the same every time.
    static let levels: [Float] = (0..<Pill.barCount).map { (i: Int) -> Float in
        let x = Double(i)
        let swing: Double = abs(sin(x * 0.62))
        let shape: Double = 0.55 + 0.45 * cos(x * 0.21)
        return Float(0.15 + 0.75 * swing * shape)
    }
}

#if DEBUG
/// Every stage of both styles, as the keyboard draws them.
struct PillGallery: View {
    let stages: [PillStage] = [.idle, .recording, .processing, .inserted, .noSpeech, .error]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(PillStyle.allCases, id: \.self) { style in
                    ForEach(stages, id: \.self) { stage in
                        HStack(spacing: 16) {
                            PillCanvas(style: style, stage: stage, level: DemoVoice.level)
                                .padding(.horizontal, 28)
                                .padding(.vertical, 14)
                                .frame(width: 236, height: 56)
                                .background(Capsule().fill(Tokens.panelLift))
                            Text("\(style.rawValue), \(Pill.label(stage))")
                                .font(.footnote)
                                .foregroundStyle(Tokens.textDim)
                        }
                    }
                }
            }
            .padding()
        }
        .background(Tokens.ink)
    }
}

#Preview("Every stage") { PillGallery() }
#Preview("Bars recording") {
    PillCanvas(style: .bars, stage: .recording, level: DemoVoice.level).frame(width: 180, height: 28).padding().background(Tokens.panelLift)
}
#Preview("Speckle recording") {
    PillCanvas(style: .speckle, stage: .recording, level: DemoVoice.level).frame(width: 180, height: 28).padding().background(Tokens.panelLift)
}
#endif
