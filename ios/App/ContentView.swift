// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

/// A quiet placeholder until Home (IOS-012) replaces it: the way to a
/// take and to the Provider screen, and nothing else.
struct ContentView: View {
    var body: some View {
        NavigationStack {
            List {
                Group {
                    NavigationLink("Dictate") { TakeRoute() }
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
    }
}

#Preview {
    ContentView()
}
