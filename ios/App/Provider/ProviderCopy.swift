// SPDX-License-Identifier: GPL-3.0-only
// The Provider screen's words, in one place: plain, sentence case, and
// for every failure what happened and how to fix it (ios/prd.json
// conventions.design).
import Foundation
import MurmurCore

extension ConnectionVerdict {
    /// A short title and the sentence under it.
    func words(provider: String) -> (title: String, detail: String) {
        switch self {
        case .works:
            return ("Works", "murmur reached \(provider) with this key.")
        case .keyRejected(let status) where status == 403:
            return ("Key rejected", "\(provider) turned this key away (code 403). Check the key, and that your \(provider) account is active.")
        case .keyRejected:
            return ("Key rejected", "\(provider) did not accept this key. Copy a fresh one from \(provider), paste it here, and save it.")
        case .noConnection:
            return ("No connection", "murmur could not reach \(provider). Check that this iPhone is online, then test again.")
        case .providerMessage(let message):
            return ("\(provider) says", message)
        }
    }

    var isSuccess: Bool { self == .works }
}

extension KeyNote {
    var words: String {
        switch self {
        case .looksLike(let provider):
            return "This looks like a \(provider) key. It works only with \(provider)."
        case .expected(let prefixes, let provider):
            return "\(provider) keys start with \(prefixes.joined(separator: " or ")). Check that you copied the whole key."
        }
    }
}

enum ProviderName {
    /// A preset's name, else the custom address's host, else a plain stand-in.
    static func of(_ preset: ProviderCatalog.Provider?, baseUrl: String) -> String {
        if let preset { return preset.name }
        if let host = URLComponents(string: baseUrl)?.host, !host.isEmpty { return host }
        return "your provider"
    }
}
