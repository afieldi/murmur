// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

/// A quiet placeholder until Home (IOS-012) replaces it: what is left of
/// setup, the way to a take, the keyboard, the session, Cleanup, and the
/// Provider screen, and nothing else. It starts the keyboard's bridge and
/// the session, opens first run on the first launch (IOS-011), and shows
/// the Recording screen when the keyboard opens murmur.
struct ContentView: View {
    @State private var opener = TakeOpener.shared
    @State private var setup = Setup.live()
    @State private var firstRun: Setup.Step?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            List {
                if !setup.isFinished {
                    SetupChecklist(setup: setup) { firstRun = $0 }
                }
                Group {
                    NavigationLink("Dictate") { TakeRoute() }
                    NavigationLink("Keyboard") { KeyboardScreen() }
                    NavigationLink("Session") { SessionRoute() }
                    NavigationLink("Cleanup") { CleanupRoute() }
                    NavigationLink("Provider and key") { ProviderRoute() }
                }
                .listRowBackground(Tokens.panel)
            }
            .scrollContentBackground(.hidden)
            .background(Tokens.ink)
            .foregroundStyle(Tokens.text)
            .navigationTitle("murmur")
            .fullScreenCover(item: $firstRun) { step in
                FirstRunScreen(setup: setup, step: step)
            }
        }
        .tint(Tokens.brand)
        .preferredColorScheme(.dark)
        .task {
            _ = KeyboardBridge.live()
            _ = Session.live()
            if !setup.seen {
                // Everything done already: nothing to walk through.
                if let next = setup.next { firstRun = next } else { setup.seen = true }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { setup.refresh() }
        }
        .onOpenURL { url in
            Task { await opener.open(url) }
        }
        .fullScreenCover(isPresented: $opener.showing) { RecordingRoute() }
    }
}

#Preview {
    ContentView()
}
