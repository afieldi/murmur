// SPDX-License-Identifier: GPL-3.0-only
// Where the provider choices live between launches: the app's own
// defaults, never the app group, since the keyboard makes no requests
// (ios/prd.json conventions.privacy). Base URLs and model ids only; the
// key stays in the key ring.
import Foundation
import MurmurCore

struct ConnectionStore {
    static let defaultsKey = "connection"
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The saved choices, or the catalog's defaults when there are none
    /// or they no longer read.
    func load(catalog: ProviderCatalog) -> ConnectionSettings {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let saved = try? JSONDecoder().decode(ConnectionSettings.self, from: data)
        else { return ConnectionSettings(defaultsFrom: catalog) }
        return saved
    }

    func save(_ settings: ConnectionSettings) {
        defaults.set(try? JSONEncoder().encode(settings), forKey: Self.defaultsKey)
    }
}

enum BundledRules {
    /// The rule files the build copied into the app (shared/).
    private static func shared() throws -> SharedData {
        guard let directory = Bundle.main.url(forResource: "shared", withExtension: nil) else {
            throw SharedDataError.missing("shared")
        }
        return SharedData(directory: directory)
    }

    static func catalog() throws -> ProviderCatalog {
        try shared().decode(ProviderCatalog.self, from: "provider-catalog.json")
    }

    /// The speech gate's numbers and the phrases models invent on silence.
    static func takeRules() throws -> TakeRules {
        let shared = try shared()
        return TakeRules(
            gate: try shared.decode(SpeechGateSpec.self, from: "speech-gate.json"),
            hallucinations: try shared.decode(HallucinationList.self, from: "hallucinations.json")
        )
    }
}
