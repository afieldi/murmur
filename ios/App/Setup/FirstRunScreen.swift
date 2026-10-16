// SPDX-License-Identifier: GPL-3.0-only
// First run (ios/prd.json IOS-011): one screen and one action per step, in
// order. A step done in Settings checks itself when you come back, and
// moves on by itself; any step can be skipped, and Finish later leaves the
// rest on Home.
import SwiftUI
import UIKit

struct FirstRunScreen: View {
    @Bindable var setup: Setup
    @State var step: Setup.Step
    @State private var addingKey = false
    @State private var practice = ""
    @State private var check = ""
    @State private var opener = TakeOpener.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(SetupCopy.progress(step))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(Tokens.textDim)
                Spacer()
                Button(SetupCopy.later) { close() }
                    .foregroundStyle(Tokens.brand)
                    .frame(minHeight: 44)
            }
            .padding(.horizontal, 24)
            StepDots(step: step, setup: setup)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            ScrollView {
                page
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            actions
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
        }
        .background(Tokens.ink)
        .foregroundStyle(Tokens.text)
        .tint(Tokens.brand)
        .onAppear {
            opener.setupUp = true
            follow()
        }
        .onDisappear {
            opener.setupUp = false
            opener.practicing = false
            dropPracticeTake()
        }
        .onChange(of: step) { was, _ in
            if was == .practice { dropPracticeTake() }
            follow()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { setup.refresh() }
            follow()
        }
        // A take started in another app while first run is up shows here,
        // since first run covers Home.
        .fullScreenCover(isPresented: $opener.showingOverSetup) { RecordingRoute() }
        // Waiting on the keyboard's report: look again every second.
        .task(id: step) {
            guard step == .keyboard || step == .fullAccess else { return }
            while !Task.isCancelled, setup.status(step) != .done {
                try? await Task.sleep(for: .seconds(1))
                setup.refresh()
            }
        }
        .onChange(of: setup.status(step)) { was, now in
            // Done in Settings or here: move on by itself, after a moment to
            // see the check.
            guard was != .done, now == .done, step != .practice else { return }
            // Only from the step that turned done: Next may have moved on.
            let from = step
            Task {
                try? await Task.sleep(for: .milliseconds(900))
                if step == from { advance() }
            }
        }
        .onChange(of: practice) { _, text in
            if !text.isEmpty { setup.practiced() }
        }
        .sheet(isPresented: $addingKey, onDismiss: { setup.refresh() }) {
            NavigationStack {
                ProviderRoute()
                    .toolbar {
                        // Back to first run once the key is saved; the step
                        // checks itself as the sheet closes.
                        ToolbarItem(placement: .confirmationAction) {
                            Button(SetupCopy.closeKey) { addingKey = false }
                        }
                    }
            }
            .preferredColorScheme(.dark)
        }
    }

    private var page: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: Self.symbol(step))
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(Tokens.brand)
                .accessibilityHidden(true)
            Text(SetupCopy.title(step))
                .font(.largeTitle.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            Text(SetupCopy.why(step))
                .font(.title3)
                .foregroundStyle(Tokens.text)
            let taps = SetupCopy.taps(step)
            if !taps.isEmpty, setup.status(step) != .done || step == .practice {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(taps.enumerated()), id: \.offset) { index, tap in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text("\(index + 1)")
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundStyle(Tokens.brand)
                                .accessibilityHidden(true)
                            Text(tap)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Step \(index + 1). \(tap)")
                    }
                }
            }
            // The box makes the keyboard appear, and it reports itself.
            if step == .keyboard || step == .fullAccess, setup.status(step) != .done {
                Box(prompt: SetupCopy.checkBox, text: $check)
            }
            if step == .practice {
                Box(prompt: SetupCopy.practiceBox, text: $practice)
                if setup.status(.practice) == .done {
                    Text(SetupCopy.practiceDone)
                        .font(.subheadline)
                        .foregroundStyle(Tokens.textDim)
                    SwipeGuide(still: reduceMotion)
                        .frame(maxWidth: .infinity)
                }
            }
            switch setup.status(step) {
            case .done:
                Note(text: SetupCopy.done, color: Tokens.ok, symbol: "checkmark.circle")
            case .denied:
                Note(text: SetupCopy.micDenied, color: Tokens.red, symbol: "mic.slash")
            case .todo, .skipped:
                EmptyView()
            }
        }
    }

    @ViewBuilder private var actions: some View {
        let status = setup.status(step)
        VStack(spacing: 4) {
            if status == .done {
                Primary(title: step == .practice ? SetupCopy.finish : SetupCopy.next) { advance() }
            } else {
                switch step {
                case .microphone where status == .denied, .keyboard, .fullAccess:
                    Primary(title: SetupCopy.openSettings) { openSettings() }
                case .microphone:
                    Primary(title: SetupCopy.allow) { Task { await setup.allowMicrophone() } }
                case .key:
                    Primary(title: SetupCopy.addKey) { addingKey = true }
                case .practice:
                    EmptyView()
                }
                if step == .keyboard {
                    Secondary(title: SetupCopy.added) { setup.keyboardAdded() }
                }
                Secondary(title: SetupCopy.skip) {
                    setup.skip(step)
                    advance()
                }
            }
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }

    /// The next step not done yet, or the end.
    private func advance() {
        guard let next = setup.step(after: step) else { return close() }
        step = next
    }

    /// A take from the practice box lands uncovered only while the box is
    /// on screen and murmur is in front.
    private func follow() {
        opener.practicing = step == .practice && scenePhase == .active
    }

    /// Leaving practice drops a practice take still starting or recording,
    /// so a take you walked away from never runs on.
    private func dropPracticeTake() {
        KeyboardBridge.live()?.hear(.cancel)
    }

    private func close() {
        setup.seen = true
        dismiss()
    }

    static func symbol(_ step: Setup.Step) -> String {
        switch step {
        case .microphone: "mic"
        case .keyboard: "keyboard"
        case .fullAccess: "lock.open"
        case .key: "key"
        case .practice: "waveform"
        }
    }
}

/// Where you are in first run: one mark per step, gold for this one,
/// filled for those done.
private struct StepDots: View {
    let step: Setup.Step
    let setup: Setup

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Setup.Step.allCases, id: \.self) { each in
                Capsule()
                    .fill(each == step ? Tokens.brand : setup.status(each) == .done ? Tokens.cream55 : Tokens.cream14)
                    .frame(height: 4)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct Box: View {
    let prompt: String
    @Binding var text: String

    var body: some View {
        TextField(prompt, text: $text, axis: .vertical)
            .lineLimit(2...5)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(Tokens.panel))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Tokens.panelEdge))
    }
}

private struct Primary: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Capsule().fill(Tokens.brand))
                .foregroundStyle(Tokens.ink)
        }
        .buttonStyle(.plain)
    }
}

private struct Secondary: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .foregroundStyle(Tokens.brand)
            .frame(maxWidth: .infinity, minHeight: 44)
    }
}

extension Setup.Step: Identifiable {
    var id: String { rawValue }
}

/// What is left of first run, on Home until it is all done.
struct SetupChecklist: View {
    let setup: Setup
    let resume: (Setup.Step) -> Void

    var body: some View {
        Section {
            ForEach(setup.remaining) { step in
                Button {
                    resume(step)
                } label: {
                    HStack {
                        Image(systemName: FirstRunScreen.symbol(step))
                            .foregroundStyle(Tokens.brand)
                            .frame(width: 24)
                            .accessibilityHidden(true)
                        Text(SetupCopy.title(step))
                            .foregroundStyle(Tokens.text)
                        Spacer()
                        if setup.status(step) == .denied {
                            Image(systemName: "exclamationmark.circle")
                                .foregroundStyle(Tokens.red)
                                .accessibilityLabel("Needs attention")
                        }
                    }
                    .contentShape(Rectangle())
                }
            }
        } header: {
            SectionTitle(SetupCopy.homeTitle)
        } footer: {
            Text(SetupCopy.homeFooter).foregroundStyle(Tokens.textDim)
        }
        .listRowBackground(Tokens.panel)
    }
}
