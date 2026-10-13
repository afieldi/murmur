// SPDX-License-Identifier: GPL-3.0-only
// Where the keyboard's first tap lands (ios/prd.json IOS-009): murmur,
// already recording, with the live waveform large and a guide along the
// bottom edge showing the swipe right that takes you back to your app.
// Everything you say from the moment it opens counts. The screen closes
// itself when the take ends; until the take is recording it says Starting
// and offers Close, so it never holds you. Amber shows only while live.
import SwiftUI

struct RecordingScreen: View {
    let model: TakeModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            if model.state == .micOff || model.state == .micFailed {
                Note(text: SessionCopy.micOff, color: Tokens.red, symbol: "mic.slash")
                Button(SessionCopy.close) { dismiss() }
                    .foregroundStyle(Tokens.brand)
                    .frame(minHeight: 44)
                Spacer()
            } else {
                LiveWave(model: model)
                    .frame(height: 160)
                    .accessibilityHidden(true)
                HStack(spacing: 10) {
                    Circle().fill(model.isRecording ? Tokens.amber : Tokens.textDim).frame(width: 10, height: 10)
                    Text(model.isRecording ? SessionCopy.recording : SessionCopy.starting)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Tokens.text)
                }
                .accessibilityElement(children: .combine)
                if model.isRecording {
                    Button {
                        Task { await model.stop() }
                    } label: {
                        Text(SessionCopy.stop)
                            .font(.body.weight(.semibold))
                            .padding(.horizontal, 32)
                            .frame(minHeight: 44)
                            .overlay(Capsule().stroke(Tokens.amber, lineWidth: 1.5))
                    }
                    .foregroundStyle(Tokens.amber)
                } else {
                    Button(SessionCopy.close) { dismiss() }
                        .foregroundStyle(Tokens.brand)
                        .frame(minHeight: 44)
                }
                Spacer()
                SwipeGuide(still: reduceMotion)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tokens.ink)
        .onChange(of: model.isRecording) { was, now in
            if was, !now { dismiss() }
        }
    }
}

/// The take's loudness over the last moments, as bars that scroll from
/// right to left: live amber while recording, dry and dim otherwise.
struct LiveWave: View {
    let model: TakeModel
    @State private var levels = [Float](repeating: 0, count: 48)

    var body: some View {
        let color = model.isRecording ? Tokens.amber : Tokens.textDim
        Canvas { context, size in
            let gap: CGFloat = 4
            let width = (size.width - gap * CGFloat(levels.count - 1)) / CGFloat(levels.count)
            for (index, level) in levels.enumerated() {
                let height = max(width, CGFloat(level) * size.height)
                let bar = CGRect(x: CGFloat(index) * (width + gap), y: (size.height - height) / 2, width: width, height: height)
                context.fill(Path(roundedRect: bar, cornerRadius: width / 2), with: .color(color))
            }
        }
        .task {
            while !Task.isCancelled {
                levels.removeFirst()
                levels.append(model.isRecording ? model.level : 0)
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }
}

/// The way back: a dot that slides right along a track at the bottom
/// edge, where the swipe goes, or with Reduce Motion a still arrow, and
/// one sentence either way.
struct SwipeGuide: View {
    let still: Bool
    @State private var moved = false

    var body: some View {
        VStack(spacing: 12) {
            Text(still ? SessionCopy.guideStill : SessionCopy.guide)
                .font(.footnote)
                .foregroundStyle(Tokens.textDim)
                .multilineTextAlignment(.center)
            if still {
                Image(systemName: "arrow.right")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Tokens.text)
                    .accessibilityHidden(true)
            } else {
                Capsule()
                    .fill(Tokens.cream14)
                    .frame(width: 160, height: 6)
                    .overlay(alignment: .leading) {
                        Circle()
                            .fill(Tokens.text)
                            .frame(width: 18, height: 18)
                            .offset(x: moved ? 142 : 0)
                    }
                    .accessibilityHidden(true)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false)) { moved = true }
                    }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// What happens when the keyboard opens murmur with a take link: the
/// session starts, the take starts under the keyboard's id, and the
/// Recording screen shows until the take ends.
@Observable @MainActor final class TakeOpener {
    static let shared = TakeOpener()
    var showing = false

    func open(_ url: URL) async {
        guard let id = TakeLink.take(in: url), let session = Session.live(), let bridge = KeyboardBridge.live(), bridge.opened(id) else { return }
        showing = true
        _ = await session.begin()
    }
}

/// The Recording screen on the app's one take model.
struct RecordingRoute: View {
    var body: some View {
        if let model = TakeModel.live() {
            RecordingScreen(model: model)
        }
    }
}
