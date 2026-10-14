// SPDX-License-Identifier: GPL-3.0-only
// New note (ios/prd.json IOS-023): one button to talk, as on Dictate, and
// the words kept as a note instead of offered to copy. The take still
// lands in your takes on Home, as every take does.
import MurmurCore
import SwiftUI

enum NoteTake {
    struct Kept: Equatable {
        let words: String
        /// Where the note landed (inbox), or nil when it could not be saved.
        let place: String?
    }

    /// A take that just came back as words is saved as a note; any other
    /// change saves nothing, so words already on screen are never saved twice.
    @MainActor static func keep(from old: TakeModel.State, to new: TakeModel.State, notes: Notes, at when: Date = .now) -> Kept? {
        guard old == .transcribing, case .words(let words) = new else { return nil }
        return Kept(words: words, place: notes.save(words, at: when))
    }
}

struct NoteTakeRoute: View {
    /// Opened by the control, the Action Button, or the icon: listen at once.
    var startNow = false
    @State private var model: TakeModel?
    @State private var notes: Notes?
    @State private var failed = false

    var body: some View {
        Group {
            if let model, let notes {
                NoteTakeScreen(model: model, notes: notes, startNow: startNow)
            } else if failed {
                Note(text: "murmur could not read its rules. Reinstall murmur to fix it.", color: Tokens.red, symbol: "exclamationmark.triangle")
                    .padding()
            }
        }
        .task {
            guard model == nil || notes == nil else { return }
            model = TakeModel.live()
            notes = Notes.live()
            failed = model == nil || notes == nil
        }
    }
}

struct NoteTakeScreen: View {
    let model: TakeModel
    let notes: Notes
    var startNow = false
    @State private var kept: NoteTake.Kept?
    @State private var started = false

    var body: some View {
        List {
            Section {
                TakeButton(model: model)
            } footer: {
                Text(NotesCopy.newNoteHint).foregroundStyle(Tokens.textDim)
            }
            .listRowBackground(Tokens.panel)

            if let kept {
                Section {
                    Text(kept.words)
                        .textSelection(.enabled)
                    if let place = kept.place {
                        Outcome(title: Pad.noted(place), detail: notes.state.newest?.place ?? "", color: Tokens.brand, symbol: "note.text")
                    } else {
                        Outcome(title: "Not saved", detail: NotesCopy.notSaved, color: Tokens.red, symbol: "xmark.circle")
                    }
                }
                .listRowBackground(Tokens.panel)
            } else if model.state.hasResult, !model.state.isWords {
                Section {
                    TakeResult(state: model.state)
                }
                .listRowBackground(Tokens.panel)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Tokens.ink)
        .foregroundStyle(Tokens.text)
        .tint(Tokens.brand)
        .navigationTitle(NotesCopy.newNote)
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.impact(weight: .light), trigger: model.isRecording)
        .onChange(of: model.state) { old, new in
            if new.isRecording { kept = nil }
            if let saved = NoteTake.keep(from: old, to: new, notes: notes) { kept = saved }
        }
        .task {
            // Once per visit, and never over a take already running.
            guard startNow, !started else { return }
            started = true
            if !model.isRecording, !model.isBusy { await model.toggle() }
        }
        .onDisappear { model.cancel() }
    }
}

extension TakeModel.State {
    var isWords: Bool {
        if case .words = self { true } else { false }
    }
}
