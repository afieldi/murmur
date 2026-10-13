// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

/// A quiet placeholder until Home (IOS-012) replaces it: the way to a
/// take, the keyboard, the session, Cleanup, and the Provider screen, and
/// nothing else. It starts the keyboard's bridge and the session, and shows
/// the Recording screen when the keyboard opens murmur.
struct ContentView: View {
    @State private var opener = TakeOpener.shared

    var body: some View {
        NavigationStack {
            List {
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
        }
        .tint(Tokens.brand)
        .preferredColorScheme(.dark)
        .task {
            _ = KeyboardBridge.live()
            _ = Session.live()
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
